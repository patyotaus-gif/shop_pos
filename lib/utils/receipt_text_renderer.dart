import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shapes receipt text with Flutter, including Thai mark-to-mark positioning.
/// Each block is a small 300 dpi image, rather than one receipt-sized bitmap.
/// An invisible text layer keeps the original Unicode available for searching.
class ReceiptTextRenderer {
  static const _family = 'Pokpok Receipt Thai';
  static Future<void>? _fonts;
  static const _scale = 300 / 72;

  static Future<void> loadFonts() => _fonts ??= _loadFonts();

  static Future<void> _loadFonts() async {
    final loader = FontLoader(_family)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Bold.ttf'));
    await loader.load();
  }

  Future<pw.SizedBox> text(String value,
      {required double maxWidth,
      pw.TextStyle? style,
      pw.TextAlign textAlign = pw.TextAlign.left}) async {
    await loadFonts();
    final size = style?.fontSize ?? 10;
    final bold = style?.fontWeight == pw.FontWeight.bold;
    // A small inset protects overhanging glyphs and antialiased edge pixels.
    const inset = 1.0;
    // Thai marks may extend beyond the font's reported ascent. Line height
    // alone does not reserve this space above the first line of a block.
    final verticalInset = size * .35;
    if (!maxWidth.isFinite || maxWidth <= 2 * inset) {
      throw ArgumentError.value(
          maxWidth, 'maxWidth', 'Text width is too small');
    }
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: _family,
      fontSize: size,
      fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      textDirection: ui.TextDirection.ltr,
      textAlign: textAlign == pw.TextAlign.center
          ? ui.TextAlign.center
          : ui.TextAlign.left,
      height: 1.35,
    ))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xff000000)))
      ..addText(value);
    final paragraph = builder.build();
    ui.Picture? picture;
    ui.Image? image;
    try {
      paragraph.layout(ui.ParagraphConstraints(width: maxWidth - 2 * inset));
      final width = math.min(
          maxWidth,
          math.max(1.0, paragraph.maxIntrinsicWidth.ceilToDouble()) +
              2 * inset);
      paragraph.layout(ui.ParagraphConstraints(width: width - 2 * inset));
      final height = paragraph.height.ceilToDouble() + verticalInset + inset;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(_scale);
      canvas.drawParagraph(paragraph, ui.Offset(inset, verticalInset));
      picture = recorder.endRecording();
      image = await picture.toImage(
          (width * _scale).ceil(), (height * _scale).ceil());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not render receipt text');
      return pw.SizedBox(
        width: width,
        height: height,
        child: pw.Stack(children: [
          pw.Positioned.fill(
            child: pw.ClipRect(
              child: pw.Text(value,
                  textAlign: textAlign,
                  style: (style ?? const pw.TextStyle())
                      .copyWith(renderingMode: PdfTextRenderingMode.invisible)),
            ),
          ),
          pw.Image(pw.MemoryImage(bytes.buffer.asUint8List()),
              width: width, height: height, fit: pw.BoxFit.fill),
        ]),
      );
    } finally {
      image?.dispose();
      picture?.dispose();
      paragraph.dispose();
    }
  }
}
