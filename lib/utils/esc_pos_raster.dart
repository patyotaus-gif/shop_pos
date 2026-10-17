import 'dart:typed_data';

/// ESC/POS GS v 0, normal-size raster bands. No cut command: portable printers
/// commonly have a manual tear bar. White/transparent pixels remain white.
class EscPosRaster {
  static Uint8List encodeRgba(Uint8List rgba, int width, int height) {
    if (width <= 0 ||
        width > 576 ||
        height <= 0 ||
        height > 12000 ||
        rgba.length != width * height * 4) {
      throw ArgumentError('Invalid raster dimensions');
    }
    final bytes = BytesBuilder(copy: false);
    final rowBytes = (width + 7) ~/ 8;
    for (var top = 0; top < height; top += 64) {
      final rows = (height - top).clamp(1, 64);
      bytes.add([0x1d, 0x76, 0x30, 0, rowBytes & 255, rowBytes >> 8, rows, 0]);
      final band = Uint8List(rowBytes * rows);
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < width; x++) {
          final index = ((top + y) * width + x) * 4;
          final alpha = rgba[index + 3];
          final luminance = (rgba[index] * 299 +
                  rgba[index + 1] * 587 +
                  rgba[index + 2] * 114) ~/
              1000;
          final onWhite = (luminance * alpha + 255 * (255 - alpha)) ~/ 255;
          if (onWhite < 160) band[y * rowBytes + x ~/ 8] |= 0x80 >> (x % 8);
        }
      }
      bytes.add(band);
    }
    return bytes.takeBytes();
  }
}
