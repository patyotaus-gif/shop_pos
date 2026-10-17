import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shop_pos/utils/receipt_logo.dart';

void main() {
  test('removes white or transparent upload padding without cropping artwork',
      () {
    for (final transparent in [false, true]) {
      final source = img.Image(width: 400, height: 400, numChannels: 4);
      img.fill(source,
          color: img.ColorRgba8(255, 255, 255, transparent ? 0 : 255));
      img.fillRect(source,
          x1: 150,
          y1: 170,
          x2: 249,
          y2: 229,
          color: img.ColorRgba8(120, 20, 20, 255));
      final result = img.decodePng(
          ReceiptLogo.prepare(Uint8List.fromList(img.encodePng(source)))!)!;
      expect(result.width, 104);
      expect(result.height, 64);
      expect(result.getPixel(2, 2).r, 120);
      expect(result.getPixel(101, 61).a, 255);
    }
  });
  test('edge artwork is preserved and invalid or empty artwork is omitted', () {
    final source = img.Image(width: 20, height: 10);
    img.fill(source, color: img.ColorRgb8(10, 10, 10));
    final result = img.decodePng(
        ReceiptLogo.prepare(Uint8List.fromList(img.encodePng(source)))!)!;
    expect(result.width, 20);
    expect(result.height, 10);
    img.fill(source, color: img.ColorRgb8(255, 255, 255));
    expect(
        ReceiptLogo.prepare(Uint8List.fromList(img.encodePng(source))), isNull);
    expect(ReceiptLogo.prepare(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
