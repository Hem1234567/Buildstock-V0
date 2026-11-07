import 'dart:typed_data';

/// A 1-bit-per-pixel image ready for the ESC/POS raster command.
class MonoBitmap {
  MonoBitmap({required this.width, required this.height, required this.data});

  /// Width in dots. Always a multiple of 8.
  final int width;
  final int height;

  /// Row-major bytes, most significant bit first, 1 = black.
  final Uint8List data;

  int get bytesPerRow => width ~/ 8;

  /// Converts RGBA pixels to black and white, scaling to [targetWidth] dots.
  /// Transparent pixels are treated as white.
  factory MonoBitmap.fromRgba(
    Uint8List rgba,
    int sourceWidth,
    int sourceHeight, {
    required int targetWidth,
    int threshold = 170,
  }) {
    final width = (targetWidth ~/ 8) * 8;
    final scale = sourceWidth / width;
    final height = (sourceHeight / scale).round().clamp(1, 1 << 15);
    final bytesPerRow = width ~/ 8;
    final out = Uint8List(bytesPerRow * height);

    for (var y = 0; y < height; y++) {
      final y0 = (y * scale).floor();
      var y1 = ((y + 1) * scale).ceil();
      if (y1 <= y0) y1 = y0 + 1;
      if (y1 > sourceHeight) y1 = sourceHeight;
      for (var x = 0; x < width; x++) {
        final x0 = (x * scale).floor();
        var x1 = ((x + 1) * scale).ceil();
        if (x1 <= x0) x1 = x0 + 1;
        if (x1 > sourceWidth) x1 = sourceWidth;

        var total = 0;
        var count = 0;
        for (var sy = y0; sy < y1; sy++) {
          final rowStart = sy * sourceWidth * 4;
          for (var sx = x0; sx < x1; sx++) {
            final i = rowStart + sx * 4;
            final alpha = rgba[i + 3];
            final luminance =
                (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
            // Blend with white by alpha.
            total += (luminance * alpha + 255 * (255 - alpha)) ~/ 255;
            count++;
          }
        }
        final average = count == 0 ? 255 : total ~/ count;
        if (average < threshold) {
          out[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return MonoBitmap(width: width, height: height, data: out);
  }
}

/// Minimal ESC/POS encoder. Pages are sent as raster images so any language
/// (including Tamil) prints exactly as it appears in the PDF.
abstract final class EscPos {
  static const List<int> initialize = [0x1B, 0x40];
  static const List<int> cut = [0x1D, 0x56, 0x42, 0x00];

  static List<int> feed(int lines) => [0x1B, 0x64, lines.clamp(0, 255)];

  /// `GS v 0` raster bit image, split into bands so small printer buffers
  /// are never overrun.
  static List<int> raster(MonoBitmap bitmap, {int bandHeight = 128}) {
    final out = <int>[];
    final bytesPerRow = bitmap.bytesPerRow;
    for (var top = 0; top < bitmap.height; top += bandHeight) {
      final rows = (top + bandHeight > bitmap.height)
          ? bitmap.height - top
          : bandHeight;
      out.addAll([
        0x1D,
        0x76,
        0x30,
        0x00,
        bytesPerRow & 0xFF,
        (bytesPerRow >> 8) & 0xFF,
        rows & 0xFF,
        (rows >> 8) & 0xFF,
      ]);
      out.addAll(
        bitmap.data.sublist(top * bytesPerRow, (top + rows) * bytesPerRow),
      );
    }
    return out;
  }

  /// A complete print job: initialise, print each page, feed and cut.
  static Uint8List job(
    List<MonoBitmap> pages, {
    int copies = 1,
    int feedLines = 4,
    bool autoCut = true,
  }) {
    final out = <int>[];
    for (var copy = 0; copy < copies.clamp(1, 10); copy++) {
      out.addAll(initialize);
      for (final page in pages) {
        out.addAll(raster(page));
      }
      out.addAll(feed(feedLines));
      if (autoCut) out.addAll(cut);
    }
    return Uint8List.fromList(out);
  }

  /// A plain ASCII test slip used by "Test print".
  static Uint8List testSlip(String title, List<String> lines) {
    final out = <int>[...initialize];
    out.addAll([0x1B, 0x61, 0x01]); // centre
    out.addAll([0x1B, 0x45, 0x01]); // bold on
    out.addAll(_ascii('$title\n'));
    out.addAll([0x1B, 0x45, 0x00]); // bold off
    out.addAll([0x1B, 0x61, 0x00]); // left
    for (final line in lines) {
      out.addAll(_ascii('$line\n'));
    }
    out.addAll(feed(4));
    out.addAll(cut);
    return Uint8List.fromList(out);
  }

  static List<int> _ascii(String text) => [
    for (final unit in text.codeUnits) unit < 128 ? unit : 0x3F,
  ];
}
