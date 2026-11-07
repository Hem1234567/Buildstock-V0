import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:buildstock/core/printing/escpos.dart';
import 'package:buildstock/core/printing/thermal_printer_service.dart';

Uint8List _rgba(int width, int height, {required bool black}) {
  final data = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final v = black ? 0 : 255;
    data[i * 4] = v;
    data[i * 4 + 1] = v;
    data[i * 4 + 2] = v;
    data[i * 4 + 3] = 255;
  }
  return data;
}

void main() {
  group('MonoBitmap', () {
    test('keeps width a multiple of 8 and scales height', () {
      final bitmap = MonoBitmap.fromRgba(
        _rgba(200, 100, black: false),
        200,
        100,
        targetWidth: 100,
      );
      expect(bitmap.width, 96);
      expect(bitmap.width % 8, 0);
      expect(bitmap.height, greaterThan(40));
      expect(bitmap.data.length, bitmap.bytesPerRow * bitmap.height);
    });

    test('white pixels stay unset and black pixels are set', () {
      final white = MonoBitmap.fromRgba(
        _rgba(16, 4, black: false),
        16,
        4,
        targetWidth: 16,
      );
      final black = MonoBitmap.fromRgba(
        _rgba(16, 4, black: true),
        16,
        4,
        targetWidth: 16,
      );
      expect(white.data.every((byte) => byte == 0), isTrue);
      expect(black.data.every((byte) => byte == 0xFF), isTrue);
    });

    test('transparent pixels print as white', () {
      final data = Uint8List(8 * 1 * 4); // fully transparent black
      final bitmap = MonoBitmap.fromRgba(data, 8, 1, targetWidth: 8);
      expect(bitmap.data.single, 0);
    });
  });

  group('EscPos', () {
    test('raster command header carries width and height', () {
      final bitmap = MonoBitmap(width: 16, height: 3, data: Uint8List(2 * 3));
      final bytes = EscPos.raster(bitmap);
      expect(bytes.sublist(0, 8), [0x1D, 0x76, 0x30, 0, 2, 0, 3, 0]);
      expect(bytes.length, 8 + 6);
    });

    test('tall images are split into bands', () {
      final bitmap = MonoBitmap(width: 8, height: 300, data: Uint8List(300));
      final bytes = EscPos.raster(bitmap, bandHeight: 128);
      // 128 + 128 + 44 rows, each with an 8 byte header.
      expect(bytes.length, 300 + 3 * 8);
    });

    test('a job initialises, feeds and cuts, once per copy', () {
      final bitmap = MonoBitmap(width: 8, height: 1, data: Uint8List(1));
      final one = EscPos.job([bitmap]);
      final two = EscPos.job([bitmap], copies: 2);
      expect(one.sublist(0, 2), [0x1B, 0x40]);
      expect(one.sublist(one.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(two.length, one.length * 2);
    });

    test('test slip replaces non-ASCII characters', () {
      final bytes = EscPos.testSlip('Hi', ['₹ 10']);
      expect(bytes.contains(0x3F), isTrue);
    });
  });

  group('PrintSettings', () {
    test('defaults to the Android print dialog', () {
      final settings = PrintSettings.fromMap(const {});
      expect(settings.connection, PrinterConnection.system);
      expect(settings.isDirect, isFalse);
      expect(settings.paper, 'a4');
    });

    test('a network printer needs a host', () {
      expect(
        PrintSettings.fromMap(const {PrinterSettingKeys.connection: 'network'})
            .isDirect,
        isFalse,
      );
      final ready = PrintSettings.fromMap(const {
        PrinterSettingKeys.connection: 'network',
        PrinterSettingKeys.host: '192.168.1.50',
        PrinterSettingKeys.port: '9100',
        PrinterSettingKeys.paper: '58',
      });
      expect(ready.isDirect, isTrue);
      expect(ready.isThermalPaper, isTrue);
      expect(ready.dotWidth, 384);
    });

    test('80 mm paper prints 576 dots and copies are clamped', () {
      final settings = PrintSettings.fromMap(const {
        PrinterSettingKeys.paper: '80',
        PrinterSettingKeys.copies: '99',
      });
      expect(settings.dotWidth, 576);
      expect(settings.copies, 5);
    });
  });
}
