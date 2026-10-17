import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Trim empty upload padding for display only; never modify the stored logo.
class ReceiptLogo {
  static Uint8List? prepare(Uint8List bytes) {
    try {
      final source = img.decodeImage(bytes);
      if (source == null) return null;
      var left = source.width;
      var top = source.height;
      var right = -1;
      var bottom = -1;
      for (final pixel in source) {
        // Ignore transparent and near-white padding, retaining coloured artwork.
        if (pixel.a > 16 && (pixel.r < 245 || pixel.g < 245 || pixel.b < 245)) {
          if (pixel.x < left) left = pixel.x;
          if (pixel.x > right) right = pixel.x;
          if (pixel.y < top) top = pixel.y;
          if (pixel.y > bottom) bottom = pixel.y;
        }
      }
      if (right < left) return null;
      // Retain a small safety border for antialiased edges.
      left = (left - 2).clamp(0, source.width - 1);
      top = (top - 2).clamp(0, source.height - 1);
      right = (right + 2).clamp(0, source.width - 1);
      bottom = (bottom + 2).clamp(0, source.height - 1);
      return Uint8List.fromList(img.encodePng(img.copyCrop(source,
          x: left, y: top, width: right - left + 1, height: bottom - top + 1)));
    } catch (_) {
      // An unreadable logo must not prevent printing the receipt.
      return null;
    }
  }
}
