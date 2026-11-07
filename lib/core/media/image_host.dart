import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// External image hosts. Firebase Storage is intentionally not used (Spark
/// plan), so photos are compressed on the device and uploaded to a free host.
enum ImageHostProvider { imgbb, cloudinary }

abstract final class ImageHostKeys {
  static const provider = 'image_host_provider';
  static const imgbbKey = 'imgbb_api_key';
  static const cloudName = 'cloudinary_cloud_name';
  static const uploadPreset = 'cloudinary_upload_preset';
}

class ImageHostConfig {
  const ImageHostConfig({
    this.provider = ImageHostProvider.imgbb,
    this.imgbbApiKey = '',
    this.cloudinaryCloudName = '',
    this.cloudinaryUploadPreset = '',
  });

  final ImageHostProvider provider;
  final String imgbbApiKey;
  final String cloudinaryCloudName;
  final String cloudinaryUploadPreset;

  static const _envImgbb = String.fromEnvironment('IMGBB_API_KEY');
  static const _envCloud = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
  static const _envPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

  bool get isConfigured => switch (provider) {
    ImageHostProvider.imgbb => imgbbApiKey.trim().isNotEmpty,
    ImageHostProvider.cloudinary =>
      cloudinaryCloudName.trim().isNotEmpty &&
          cloudinaryUploadPreset.trim().isNotEmpty,
  };

  /// Builds the configuration from stored settings. Build-time values supplied
  /// with `--dart-define` are used when the setting is empty.
  factory ImageHostConfig.fromSettings(Map<String, String> settings) {
    String pick(String key, String fallback) {
      final value = (settings[key] ?? '').trim();
      return value.isEmpty ? fallback : value;
    }

    final providerName = pick(
      ImageHostKeys.provider,
      _envCloud.isNotEmpty && _envImgbb.isEmpty ? 'cloudinary' : 'imgbb',
    );
    return ImageHostConfig(
      provider: providerName == 'cloudinary'
          ? ImageHostProvider.cloudinary
          : ImageHostProvider.imgbb,
      imgbbApiKey: pick(ImageHostKeys.imgbbKey, _envImgbb),
      cloudinaryCloudName: pick(ImageHostKeys.cloudName, _envCloud),
      cloudinaryUploadPreset: pick(ImageHostKeys.uploadPreset, _envPreset),
    );
  }
}

class ImageUploadException implements Exception {
  const ImageUploadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UploadedImage {
  const UploadedImage({required this.url, this.deleteUrl, this.remoteId});

  final String url;
  final String? deleteUrl;
  final String? remoteId;
}

/// Uploads a compressed image and returns its public HTTPS address.
class ImageUploader {
  const ImageUploader();

  Future<UploadedImage> upload({
    required ImageHostConfig config,
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!config.isConfigured) {
      throw const ImageUploadException(
        'Image hosting is not configured. Open Settings > Photo hosting.',
      );
    }
    switch (config.provider) {
      case ImageHostProvider.imgbb:
        final body = await _postMultipart(
          Uri.parse(
            'https://api.imgbb.com/1/upload?key='
            '${Uri.encodeQueryComponent(config.imgbbApiKey.trim())}',
          ),
          fields: const {},
          fileField: 'image',
          fileName: fileName,
          bytes: bytes,
        );
        return parseImgbbResponse(body);
      case ImageHostProvider.cloudinary:
        final body = await _postMultipart(
          Uri.parse(
            'https://api.cloudinary.com/v1_1/'
            '${Uri.encodeComponent(config.cloudinaryCloudName.trim())}'
            '/image/upload',
          ),
          fields: {'upload_preset': config.cloudinaryUploadPreset.trim()},
          fileField: 'file',
          fileName: fileName,
          bytes: bytes,
        );
        return parseCloudinaryResponse(body);
    }
  }

  static UploadedImage parseImgbbResponse(String body) {
    final decoded = _decode(body);
    final data = decoded['data'];
    if (decoded['success'] == false || data is! Map) {
      throw ImageUploadException(
        _errorText(decoded, 'ImgBB rejected the upload'),
      );
    }
    final url = (data['url'] ?? data['display_url'])?.toString() ?? '';
    if (!url.startsWith('http')) {
      throw const ImageUploadException('ImgBB returned no image address');
    }
    return UploadedImage(
      url: url,
      deleteUrl: data['delete_url']?.toString(),
      remoteId: data['id']?.toString(),
    );
  }

  static UploadedImage parseCloudinaryResponse(String body) {
    final decoded = _decode(body);
    final url = (decoded['secure_url'] ?? decoded['url'])?.toString() ?? '';
    if (!url.startsWith('http')) {
      throw ImageUploadException(
        _errorText(decoded, 'Cloudinary rejected the upload'),
      );
    }
    return UploadedImage(url: url, remoteId: decoded['public_id']?.toString());
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ImageUploadException(
      'The image host returned an unreadable reply',
    );
  }

  static String _errorText(Map<String, dynamic> decoded, String fallback) {
    final error = decoded['error'];
    if (error is Map && error['message'] != null) {
      return error['message'].toString();
    }
    if (error is String && error.isNotEmpty) return error;
    return fallback;
  }

  Future<String> _postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required String fileField,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final boundary = '----buildstock${DateTime.now().microsecondsSinceEpoch}';
    final builder = BytesBuilder();
    void text(String value) => builder.add(utf8.encode(value));

    fields.forEach((name, value) {
      text(
        '--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n'
        '$value\r\n',
      );
    });
    text(
      '--$boundary\r\nContent-Disposition: form-data; name="$fileField"; '
      'filename="$fileName"\r\nContent-Type: image/jpeg\r\n\r\n',
    );
    builder.add(bytes);
    text('\r\n--$boundary--\r\n');
    final body = builder.takeBytes();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final reply = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String detail = reply;
        try {
          detail = _errorText(_decode(reply), reply);
        } catch (_) {}
        if (detail.length > 160) detail = detail.substring(0, 160);
        throw ImageUploadException(
          'Upload failed (${response.statusCode}): $detail',
        );
      }
      return reply;
    } on SocketException {
      throw const ImageUploadException('No internet connection');
    } finally {
      client.close(force: true);
    }
  }
}
