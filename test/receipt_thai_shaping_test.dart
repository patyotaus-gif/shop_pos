import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shop_pos/utils/receipt_text_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Thai vowel and tone combinations retain their shaped appearance',
      () async {
    final renderer = ReceiptTextRenderer();
    for (final bold in [false, true]) {
      final block = await renderer.text(
        'น้ำ น้ำจิ้ม น้ำผึ้ง กุ้ง\n'
        'หมู่บ้าน ชั้นที่ ผู้เสียภาษี\n'
        'ปู่ ยี่ห้อ ก๋วยเตี๋ยว ปูผัดผงกะหรี่',
        maxWidth: 220,
        style: pw.TextStyle(
            fontSize: 12,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      );
      expect(block.width, lessThanOrEqualTo(220));
      final stack = block.child! as pw.Stack;
      final image = stack.children.last as pw.Image;
      final bytes = (image.image as pw.MemoryImage).bytes;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      try {
        final pixels =
            (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
        final width = frame.image.width;
        final height = frame.image.height;
        // No ink may touch an image edge: marks outside reported font metrics
        // must not be clipped when the shaped block is embedded in the PDF.
        for (var x = 0; x < width; x++) {
          expect(pixels[x * 4 + 3], 0);
          expect(pixels[((height - 1) * width + x) * 4 + 3], 0);
        }
        for (var y = 0; y < height; y++) {
          expect(pixels[(y * width) * 4 + 3], 0);
          expect(pixels[(y * width + width - 1) * 4 + 3], 0);
        }
        await expectLater(
            frame.image,
            matchesGoldenFile(
                'goldens/receipt_thai_${bold ? 'bold' : 'regular'}.png'));
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    }
  });
}
