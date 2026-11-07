import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/domain/enums.dart';
import 'package:buildstock/core/media/image_host.dart';
import 'package:buildstock/core/utils/ids.dart';
import 'package:buildstock/core/utils/json.dart';

class CapturedImage {
  const CapturedImage({required this.id, required this.path});

  final String id;

  /// Compressed copy stored inside the app's documents folder.
  final String path;
}

/// Captures, compresses, stores and uploads photos.
///
/// A picture is first saved as a compressed local file so every screen works
/// offline. When the device is online and an image host is configured, the file
/// is uploaded and every stored reference to the local path is replaced with
/// the public URL, which then syncs to the other devices through Firestore.
class ImageService {
  ImageService(this.services, {ImageUploader uploader = const ImageUploader()})
    : _uploader = uploader;

  final AppServices services;
  final ImageUploader _uploader;

  bool _busy = false;

  AppDatabase get db => services.db;

  /// Columns that may hold an image reference. Used to swap a local path for
  /// the uploaded URL without needing to know which record owns the photo.
  static const List<(String table, String column, String collection)>
  referenceColumns = [
    ('products', 'main_image_ref', 'products'),
    ('products', 'gallery_json', 'products'),
    ('customers', 'photo_ref', 'customers'),
    ('suppliers', 'photo_ref', 'suppliers'),
    ('staff_members', 'photo_ref', 'staff'),
    ('drivers', 'photo_ref', 'drivers'),
    ('drivers', 'licence_doc_ref', 'drivers'),
    ('drivers', 'identity_doc_ref', 'drivers'),
    ('business_profiles', 'logo_ref', 'business_profile'),
    ('business_profiles', 'signature_ref', 'business_profile'),
    ('business_profiles', 'stamp_ref', 'business_profile'),
    ('deliveries', 'proof_image_refs', 'deliveries'),
    ('delivery_proofs', 'image_ref', 'delivery_proofs'),
    ('purchases', 'attachment_refs_json', 'purchases'),
    ('expenses', 'attachment_ref', 'expenses'),
  ];

  static const Set<String> _tablesWithoutVersion = {'business_profiles'};

  // --------------------------------------------------------------- capture

  /// Opens the camera or gallery. Returns null if the user cancels.
  Future<CapturedImage?> pick({
    required ImageSource source,
    required String ownerType,
    String role = 'primary',
    String ownerId = '',
  }) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 92,
    );
    if (picked == null) return null;
    final original = await picked.readAsBytes();
    return store(
      original,
      ownerType: ownerType,
      role: role,
      ownerId: ownerId,
      sourcePath: picked.path,
    );
  }

  /// Compresses [bytes], stores them locally and records the metadata.
  Future<CapturedImage> store(
    Uint8List bytes, {
    required String ownerType,
    String role = 'primary',
    String ownerId = '',
    String? sourcePath,
  }) async {
    final compressed = await compress(bytes, sourcePath: sourcePath);
    final id = Ids.image();
    final directory = await _imageDirectory();
    final file = File('${directory.path}/$id.jpg');
    await file.writeAsBytes(compressed, flush: true);

    var width = 0;
    var height = 0;
    try {
      final codec = await ui.instantiateImageCodec(compressed);
      final frame = await codec.getNextFrame();
      width = frame.image.width;
      height = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}

    final identity = services.identity;
    final now = DateTime.now();
    final config = await loadConfig();
    await db
        .into(db.imageMetadata)
        .insert(
          ImageMetadataCompanion.insert(
            id: id,
            shopId: Value(identity.shopId),
            ownerType: ownerType,
            ownerId: ownerId,
            role: Value(role),
            localPath: Value(file.path),
            mimeType: const Value('image/jpeg'),
            byteSize: Value(compressed.length),
            sha256: Value(sha256.convert(compressed).toString()),
            width: Value(width),
            height: Value(height),
            uploadStatus: const Value(UploadStatus.pending),
            provider: Value(config.provider.name),
            ownerUid: Value(identity.userId ?? ''),
            createdAt: now,
            updatedAt: now,
            deviceId: Value(identity.deviceId),
          ),
        );
    unawaited(uploadPending());
    return CapturedImage(id: id, path: file.path);
  }

  /// JPEG, longest side 1280 px, quality 80. Falls back to the original bytes
  /// if the platform compressor is unavailable.
  Future<Uint8List> compress(Uint8List bytes, {String? sourcePath}) async {
    if (kIsWeb) return bytes;
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty) return result;
    } catch (_) {}
    return bytes;
  }

  Future<Directory> _imageDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/images');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  // ---------------------------------------------------------------- upload

  Future<ImageHostConfig> loadConfig() async {
    final rows = await db.select(db.appSettings).get();
    return ImageHostConfig.fromSettings({
      for (final row in rows) row.key: row.value,
    });
  }

  /// Uploads every photo that is still waiting. Safe to call at any time; it
  /// quietly does nothing when hosting is not configured or the device is
  /// offline, and tries again on the next call.
  Future<int> uploadPending({int limit = 6}) async {
    if (_busy || kIsWeb) return 0;
    _busy = true;
    var uploaded = 0;
    try {
      final config = await loadConfig();
      if (!config.isConfigured) return 0;
      final rows =
          await (db.select(db.imageMetadata)
                ..where(
                  (t) =>
                      t.uploadStatus.isIn([
                        UploadStatus.pending,
                        UploadStatus.failed,
                      ]) &
                      t.deletedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
                ..limit(limit))
              .get();
      for (final row in rows) {
        final file = File(row.localPath);
        if (row.localPath.isEmpty || !await file.exists()) {
          await _setStatus(row, UploadStatus.failed);
          continue;
        }
        try {
          await _setStatus(row, UploadStatus.uploading);
          final result = await _uploader.upload(
            config: config,
            bytes: await file.readAsBytes(),
            fileName: '${row.id}.jpg',
          );
          await _completeUpload(row, result.url, config.provider.name);
          uploaded++;
        } on ImageUploadException {
          await _setStatus(row, UploadStatus.failed);
          // Offline or misconfigured: stop and retry on the next trigger.
          break;
        } catch (_) {
          await _setStatus(row, UploadStatus.failed);
        }
      }
    } finally {
      _busy = false;
    }
    return uploaded;
  }

  Future<void> _setStatus(ImageMetadataRow row, String status) async {
    await (db.update(
      db.imageMetadata,
    )..where((t) => t.id.equals(row.id))).write(
      ImageMetadataCompanion(
        uploadStatus: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> _completeUpload(
    ImageMetadataRow row,
    String url,
    String provider,
  ) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.imageMetadata,
      )..where((t) => t.id.equals(row.id))).write(
        ImageMetadataCompanion(
          remoteUrl: Value(url),
          uploadStatus: const Value(UploadStatus.uploaded),
          provider: Value(provider),
          updatedAt: Value(now),
          version: Value(row.version + 1),
          syncStatus: const Value(SyncStatus.pending),
        ),
      );
      final updated = await (db.select(
        db.imageMetadata,
      )..where((t) => t.id.equals(row.id))).getSingle();
      final identity = services.identity;
      await services.outbox.enqueue(
        shopId: identity.shopId,
        deviceId: identity.deviceId,
        userId: identity.userId,
        entityType: 'image_metadata',
        collection: 'image_metadata',
        entityId: row.id,
        payload: Json.toCloud(updated.toJson()),
        baseVersion: row.version,
        priority: 95,
      );
      await replaceReference(oldRef: row.localPath, newRef: url);
    });
  }

  /// Replaces [oldRef] with [newRef] in every record that stores an image
  /// reference and queues those records for sync.
  Future<int> replaceReference({
    required String oldRef,
    required String newRef,
  }) async {
    if (oldRef.isEmpty || oldRef == newRef) return 0;
    final identity = services.identity;
    var changed = 0;
    final now = DateTime.now();
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    for (final (table, column, collection) in referenceColumns) {
      final matches = await db
          .customSelect(
            'SELECT id FROM "$table" WHERE instr("$column", ?) > 0',
            variables: [Variable<String>(oldRef)],
          )
          .get();
      for (final match in matches) {
        final id = match.read<String>('id');
        final hasVersion = !_tablesWithoutVersion.contains(table);
        final versionSql = hasVersion
            ? ', version = version + 1, sync_status = \'pending\''
            : '';
        final timeSql = _hasUpdatedAt(table) ? ', updated_at = ?' : '';
        await db.customStatement(
          'UPDATE "$table" SET "$column" = REPLACE("$column", ?, ?)'
          '$timeSql$versionSql WHERE id = ?',
          [oldRef, newRef, if (_hasUpdatedAt(table)) seconds, id],
        );
        final row = await db
            .customSelect(
              'SELECT * FROM "$table" WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .getSingleOrNull();
        if (row == null) continue;
        final data = Map<String, dynamic>.from(row.data);
        final version = hasVersion ? Json.asInt(data['version']) : 0;
        await services.outbox.enqueue(
          shopId: identity.shopId,
          deviceId: identity.deviceId,
          userId: identity.userId,
          entityType: table,
          collection: collection,
          entityId: id,
          payload: Json.toCloud(data),
          baseVersion: hasVersion ? version - 1 : 1,
          priority: 95,
        );
        changed++;
      }
    }
    return changed;
  }

  bool _hasUpdatedAt(String table) => table != 'delivery_proofs';

  /// Reads the stored bytes for [reference]: a local file or a downloaded URL.
  /// Used when an image must be embedded in a PDF.
  static Future<Uint8List?> loadBytes(String? reference) async {
    final value = reference?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        try {
          final request = await client.getUrl(Uri.parse(value));
          final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode != 200) return null;
          final builder = BytesBuilder();
          await for (final chunk in response) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        } finally {
          client.close(force: true);
        }
      }
      final file = File(value);
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    return null;
  }
}

final imageServiceProvider = Provider<ImageService>(
  (ref) => ImageService(ref.watch(servicesProvider)),
);
