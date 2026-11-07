import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/media/image_host.dart';

void main() {
  group('ImageHostConfig', () {
    test('is not configured without credentials', () {
      expect(const ImageHostConfig().isConfigured, isFalse);
    });

    test('ImgBB needs only an API key', () {
      final config = ImageHostConfig.fromSettings(const {
        ImageHostKeys.provider: 'imgbb',
        ImageHostKeys.imgbbKey: 'abc',
      });
      expect(config.provider, ImageHostProvider.imgbb);
      expect(config.isConfigured, isTrue);
    });

    test('Cloudinary needs a cloud name and an unsigned preset', () {
      final partial = ImageHostConfig.fromSettings(const {
        ImageHostKeys.provider: 'cloudinary',
        ImageHostKeys.cloudName: 'demo',
      });
      expect(partial.isConfigured, isFalse);
      final full = ImageHostConfig.fromSettings(const {
        ImageHostKeys.provider: 'cloudinary',
        ImageHostKeys.cloudName: 'demo',
        ImageHostKeys.uploadPreset: 'unsigned',
      });
      expect(full.isConfigured, isTrue);
    });
  });

  group('upload responses', () {
    test('parses an ImgBB success reply', () {
      final result = ImageUploader.parseImgbbResponse(
        '{"data":{"id":"x1","url":"https://i.ibb.co/a/b.jpg",'
        '"delete_url":"https://ibb.co/x1/del"},"success":true,"status":200}',
      );
      expect(result.url, 'https://i.ibb.co/a/b.jpg');
      expect(result.remoteId, 'x1');
      expect(result.deleteUrl, 'https://ibb.co/x1/del');
    });

    test('reports an ImgBB error message', () {
      expect(
        () => ImageUploader.parseImgbbResponse(
          '{"success":false,"error":{"message":"Invalid API v1 key."}}',
        ),
        throwsA(
          isA<ImageUploadException>().having(
            (e) => e.message,
            'message',
            contains('Invalid API'),
          ),
        ),
      );
    });

    test('parses a Cloudinary reply', () {
      final result = ImageUploader.parseCloudinaryResponse(
        '{"public_id":"p1","secure_url":"https://res.cloudinary.com/d/p1.jpg"}',
      );
      expect(result.url, startsWith('https://res.cloudinary.com'));
      expect(result.remoteId, 'p1');
    });

    test('rejects garbage', () {
      expect(
        () => ImageUploader.parseCloudinaryResponse('not json'),
        throwsA(isA<ImageUploadException>()),
      );
    });
  });
}
