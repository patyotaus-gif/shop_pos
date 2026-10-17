import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/esc_pos_raster.dart';
import '../utils/receipt_generator.dart';
import '../utils/receipt_text_renderer.dart';

class BluetoothPrinterConfig {
  const BluetoothPrinterConfig(
      {required this.address, required this.name, this.paperMm = 58});
  final String address;
  final String name;
  final int paperMm;
  int get dots => paperMm == 80 ? 576 : 384;
}

class BluetoothPrinterService {
  static const channel = MethodChannel('app.pokpok.pos/bluetooth_printer');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool _printing = false;

  static Future<List<BluetoothPrinterConfig>> pairedDevices() async {
    final list = await channel.invokeListMethod<dynamic>('pairedDevices') ?? [];
    return list
        .map((entry) => BluetoothPrinterConfig(
            address: entry['address'] as String, name: entry['name'] as String))
        .toList();
  }

  static Future<void> openSettings() => channel.invokeMethod('openSettings');

  static Future<BluetoothPrinterConfig?> saved() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList('bluetooth_receipt_printer_v1');
    if (values == null ||
        values.length != 3 ||
        !RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(values[0]) ||
        !['58', '80'].contains(values[2])) {
      return null;
    }
    return BluetoothPrinterConfig(
        address: values[0], name: values[1], paperMm: int.parse(values[2]));
  }

  static Future<void> save(BluetoothPrinterConfig config) async {
    if (![58, 80].contains(config.paperMm)) throw ArgumentError('paperMm');
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setStringList('bluetooth_receipt_printer_v1',
        [config.address, config.name, '${config.paperMm}']);
    if (!ok) throw StateError('บันทึกเครื่องพิมพ์ไม่สำเร็จ');
  }

  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bluetooth_receipt_printer_v1');
  }

  /// The supplied PDF must already be laid out for config.paperMm. Rasterize
  /// before opening the socket so rendering errors cannot leave a partial job.
  static Future<void> printPdf(
      Uint8List pdf, BluetoothPrinterConfig config) async {
    if (!supported) {
      throw StateError('พิมพ์ Bluetooth ตรงรองรับ Android ในรุ่นนี้');
    }
    if (_printing) throw StateError('กำลังส่งงานพิมพ์ กรุณารอ');
    if (![58, 80].contains(config.paperMm)) throw ArgumentError('paperMm');
    _printing = true;
    try {
      final bytes = BytesBuilder(copy: false)..add([0x1b, 0x40]);
      var totalRows = 0;
      var pages = 0;
      await for (final raster
          in Printing.raster(pdf, dpi: config.dots * 25.4 / config.paperMm)
              .timeout(const Duration(seconds: 30))) {
        if (raster.height > 12000 || raster.width > 1200 || ++pages > 20) {
          throw StateError('ใบเสร็จยาวเกินไป กรุณาใช้การพิมพ์ผ่านระบบ');
        }
        var bitmap = img.Image.fromBytes(
            width: raster.width,
            height: raster.height,
            bytes: raster.pixels.buffer,
            bytesOffset: raster.pixels.offsetInBytes,
            numChannels: 4);
        if (bitmap.width != config.dots) {
          bitmap = img.copyResize(bitmap, width: config.dots);
        }
        totalRows += bitmap.height;
        if (totalRows > 12000) {
          throw StateError('ใบเสร็จยาวเกินไป กรุณาใช้การพิมพ์ผ่านระบบ');
        }
        bytes.add(EscPosRaster.encodeRgba(
            bitmap.getBytes(order: img.ChannelOrder.rgba),
            bitmap.width,
            bitmap.height));
      }
      if (pages == 0) throw StateError('ไม่พบหน้าใบเสร็จสำหรับพิมพ์');
      // Explicit dot feed (~15 mm at 203 dpi) brings the footer past the tear
      // bar, independently of the printer's configured text line spacing.
      bytes.add([0x1b, 0x4a, 120]);
      await channel.invokeMethod<void>('printBytes',
          {'address': config.address, 'bytes': bytes.takeBytes()});
    } finally {
      _printing = false;
    }
  }

  static Future<Uint8List> testDocument(int paperMm) async {
    final format =
        paperMm == 80 ? ReceiptGenerator.slip80 : ReceiptGenerator.slip58;
    final renderer = ReceiptTextRenderer();
    final content = <pw.Widget>[];
    for (final line in [
      'Pokpok ทดสอบเครื่องพิมพ์',
      'กุ้ง น้ำจิ้ม ปูผัดผงกะหรี่',
      'กระดาษ $paperMm มม.',
      '0123456789   ฿123.45',
      'ไม่ใช่ใบเสร็จรับเงิน'
    ]) {
      content.add(await renderer.text(line, maxWidth: format.availableWidth));
    }
    final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final doc =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font))
          ..addPage(pw.Page(
              pageFormat: format,
              build: (_) => pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: content)));
    return doc.save();
  }

  static String errorMessage(Object error) => error is PlatformException
      ? (error.message ?? 'เชื่อมต่อเครื่องพิมพ์ไม่สำเร็จ')
      : error is StateError
          ? error.message
          : 'พิมพ์ไม่สำเร็จ ตรวจเครื่องและกระดาษก่อนลองใหม่';
}
