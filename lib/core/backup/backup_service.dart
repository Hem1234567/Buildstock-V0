import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:buildstock/core/database/app_database.dart';
import 'package:buildstock/core/database/database_provider.dart';
import 'package:buildstock/core/session/session_service.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

class BackupFileInfo {
  const BackupFileInfo({
    required this.path,
    required this.name,
    required this.modified,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final DateTime modified;
  final int sizeBytes;
}

class RestoreSummary {
  const RestoreSummary({required this.tables, required this.rows});

  final int tables;
  final int rows;
}

/// Full local backup and restore.
///
/// A backup is a gzip-compressed JSON file (`.bsbackup`) that contains every
/// table of the local SQLite database, including the sync outbox so nothing
/// waiting to upload is lost. Restoring replaces the business data of this
/// device but keeps its own identity (device ID, device code, linked shop) and
/// never lowers a document number sequence, so invoice numbers can not repeat.
class BackupService {
  BackupService(this.services);

  final AppServices services;

  static const int formatVersion = 1;
  static const String appMarker = 'buildstock';
  static const String extension = 'bsbackup';

  /// Tables never copied into a backup.
  static const Set<String> _excludedTables = {'sync_metadata', 'devices'};

  /// Settings that describe this installation and must survive a restore.
  static const Set<String> _identitySettings = {
    IdentityKeys.deviceId,
    IdentityKeys.deviceName,
    IdentityKeys.deviceCode,
    IdentityKeys.shopId,
    'last_backup_at',
  };

  AppDatabase get db => services.db;

  Map<String, TableInfo> get _tables => {
    for (final table in db.allTables) table.actualTableName: table,
  };

  // ---------------------------------------------------------------- create

  Future<Uint8List> createBackup() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final entry in _tables.entries) {
      if (_excludedTables.contains(entry.key)) continue;
      final rows = await db.customSelect('SELECT * FROM "${entry.key}"').get();
      tables[entry.key] = [
        for (final row in rows) Map<String, Object?>.from(row.data),
      ];
    }
    final tablesJson = jsonEncode(tables);
    final document = {
      'app': appMarker,
      'format': formatVersion,
      'schema': db.schemaVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': services.identity.deviceId,
      'shop_id': services.identity.shopId,
      'checksum': sha256.convert(utf8.encode(tablesJson)).toString(),
      'tables': tables,
    };
    final compressed = gzip.encode(utf8.encode(jsonEncode(document)));
    await db.setSetting('last_backup_at', DateTime.now().toIso8601String());
    return Uint8List.fromList(compressed);
  }

  static String fileName([DateTime? at]) {
    final time = at ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'buildstock-backup-${time.year}${two(time.month)}${two(time.day)}'
        '-${two(time.hour)}${two(time.minute)}.$extension';
  }

  // ----------------------------------------------------------- local files

  Future<Directory> backupDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/backups');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  Future<List<BackupFileInfo>> localBackups() async {
    final directory = await backupDirectory();
    final files = <BackupFileInfo>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.$extension')) continue;
      final stat = await entity.stat();
      files.add(
        BackupFileInfo(
          path: entity.path,
          name: entity.uri.pathSegments.last,
          modified: stat.modified,
          sizeBytes: stat.size,
        ),
      );
    }
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  Future<Uint8List> readLocal(String path) => File(path).readAsBytes();

  Future<File> writeLocalBackup({String prefix = 'auto'}) async {
    final bytes = await createBackup();
    final directory = await backupDirectory();
    final file = File('${directory.path}/$prefix-${fileName()}');
    await file.writeAsBytes(bytes, flush: true);
    await _prune(directory, keep: 7);
    return file;
  }

  Future<void> _prune(Directory directory, {required int keep}) async {
    final autos = <File>[];
    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('auto-') &&
          entity.path.endsWith('.$extension')) {
        autos.add(entity);
      }
    }
    autos.sort((a, b) => b.path.compareTo(a.path));
    for (final stale in autos.skip(keep)) {
      try {
        await stale.delete();
      } catch (_) {}
    }
  }

  /// Creates a daily snapshot when the last one is older than 20 hours.
  Future<File?> autoBackupIfDue() async {
    final enabled = await db.getSetting('auto_backup');
    if (enabled == 'false') return null;
    final last = DateTime.tryParse(
      await db.getSetting('last_auto_backup_at') ?? '',
    );
    if (last != null && DateTime.now().difference(last).inHours < 20) {
      return null;
    }
    final file = await writeLocalBackup();
    await db.setSetting(
      'last_auto_backup_at',
      DateTime.now().toIso8601String(),
    );
    return file;
  }

  // --------------------------------------------------------------- restore

  /// Validates a backup and returns its parsed document.
  static Map<String, dynamic> parse(Uint8List bytes) {
    late final String text;
    try {
      text = utf8.decode(gzip.decode(bytes));
    } catch (_) {
      throw const BackupException('This is not a BuildStock backup file.');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const BackupException('The backup file is damaged.');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != appMarker) {
      throw const BackupException('This is not a BuildStock backup file.');
    }
    final format = decoded['format'];
    if (format is! int || format > formatVersion) {
      throw const BackupException(
        'This backup was made by a newer version of BuildStock. Update the app first.',
      );
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw const BackupException('The backup file has no data.');
    }
    final checksum = sha256.convert(utf8.encode(jsonEncode(tables))).toString();
    if (decoded['checksum'] != checksum) {
      throw const BackupException(
        'The backup failed its integrity check and was not restored.',
      );
    }
    return decoded;
  }

  /// Replaces this device's business data with the backup. A safety copy of
  /// the current data is written first.
  Future<RestoreSummary> restore(Uint8List bytes) async {
    final document = parse(bytes);
    final backupTables = document['tables'] as Map<String, dynamic>;

    // Safety net: if anything goes wrong the user can restore this file.
    await writeLocalBackup(prefix: 'before-restore');

    final known = _tables;
    final currentSequences = <String, int>{};
    for (final row in await db.select(db.numberSequences).get()) {
      currentSequences[row.id] = row.nextValue;
    }
    final currentSettings = <String, String>{};
    for (final row in await db.select(db.appSettings).get()) {
      if (_identitySettings.contains(row.key)) {
        currentSettings[row.key] = row.value;
      }
    }

    var tableCount = 0;
    var rowCount = 0;
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction(() async {
        for (final entry in known.entries) {
          final name = entry.key;
          if (_excludedTables.contains(name)) continue;
          await db.customStatement('DELETE FROM "$name"');
          final rows = backupTables[name];
          if (rows is! List) continue;
          final columns = entry.value.$columns.map((c) => c.$name).toSet();
          for (final raw in rows) {
            if (raw is! Map) continue;
            final names = <String>[];
            final values = <Object?>[];
            raw.forEach((key, value) {
              if (columns.contains(key)) {
                names.add('"$key"');
                values.add(value);
              }
            });
            if (names.isEmpty) continue;
            final placeholders = List.filled(names.length, '?').join(', ');
            await db.customStatement(
              'INSERT OR REPLACE INTO "$name" (${names.join(', ')}) '
              'VALUES ($placeholders)',
              values,
            );
            rowCount++;
          }
          tableCount++;
        }

        // Keep this installation's identity.
        for (final entry in currentSettings.entries) {
          await db.setSetting(entry.key, entry.value);
        }
        // Never move a number sequence backwards.
        for (final entry in currentSequences.entries) {
          final restored = await (db.select(
            db.numberSequences,
          )..where((t) => t.id.equals(entry.key))).getSingleOrNull();
          if (restored == null || restored.nextValue < entry.value) {
            await db.customStatement(
              'INSERT OR REPLACE INTO number_sequences '
              '(id, prefix, next_value, updated_at) VALUES (?, ?, ?, ?)',
              [
                entry.key,
                restored?.prefix ?? '',
                entry.value,
                DateTime.now().millisecondsSinceEpoch ~/ 1000,
              ],
            );
          }
        }
        // Force the next sync to compare everything with the cloud.
        await db.customStatement('DELETE FROM sync_metadata');
      });
    } finally {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }
    db.markTablesUpdated(db.allTables);
    return RestoreSummary(tables: tableCount, rows: rowCount);
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(servicesProvider)),
);
