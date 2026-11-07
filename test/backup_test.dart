import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/backup/backup_service.dart';

Uint8List _backup(
  Map<String, dynamic> tables, {
  String? checksum,
  int format = 1,
}) {
  final document = {
    'app': 'buildstock',
    'format': format,
    'schema': 1,
    'tables': tables,
    'checksum':
        checksum ?? sha256.convert(utf8.encode(jsonEncode(tables))).toString(),
  };
  return Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(document))));
}

void main() {
  group('BackupService.parse', () {
    test('accepts a valid backup', () {
      final document = BackupService.parse(
        _backup({
          'products': [
            {'id': 'p1', 'name': 'Cement'},
          ],
        }),
      );
      expect((document['tables'] as Map).containsKey('products'), isTrue);
    });

    test('rejects files that are not backups', () {
      expect(
        () => BackupService.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<BackupException>()),
      );
      final other = Uint8List.fromList(
        gzip.encode(utf8.encode('{"app":"other","format":1,"tables":{}}')),
      );
      expect(() => BackupService.parse(other), throwsA(isA<BackupException>()));
    });

    test('rejects a backup whose data was changed', () {
      expect(
        () => BackupService.parse(_backup({'products': []}, checksum: 'bad')),
        throwsA(
          isA<BackupException>().having(
            (e) => e.message,
            'message',
            contains('integrity'),
          ),
        ),
      );
    });

    test('rejects a backup from a newer app version', () {
      expect(
        () => BackupService.parse(_backup({}, format: 99)),
        throwsA(isA<BackupException>()),
      );
    });

    test('file names are sortable and use the backup extension', () {
      final name = BackupService.fileName(DateTime(2026, 11, 6, 9, 5));
      expect(name, 'buildstock-backup-20261106-0905.bsbackup');
    });
  });
}
