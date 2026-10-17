import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'auth_service.dart';
import '../widgets/shop_operation.dart';
import 'bluetooth_printer_service.dart';
import '../screens/bluetooth_printer_screen.dart';
import '../utils/receipt_generator.dart';
import '../utils/receipt_text_renderer.dart';

class KitchenPrintService {
  static Stream<Map<String, Map<String, dynamic>>> watchJobs() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('kitchenPrintJobs')
          .snapshots()
          .map((s) => {for (final d in s.docs) d.id: d.data()});
  static Future<dynamic> _call(String name, Map<String, dynamic> data) =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable(name,
              options:
                  HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call({'shopId': AuthService.shopId, ...data})
          .then((r) => r.data)
          .timeout(const Duration(seconds: 25));

  static Future<Uint8List> buildTicket(Map job, {int? paperMm}) async {
    if (paperMm != null) return _buildBluetoothTicket(job, paperMm);
    final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final pdf =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm,
            marginAll: 5 * PdfPageFormat.mm),
        build: (_) => [
              if (job['reprint'] == true)
                pw.Text('สำเนา / พิมพ์ซ้ำ — ตรวจใบเดิมก่อนทำอาหาร'),
              pw.Text('ใบงานครัว • ${job['title']}',
                  style: const pw.TextStyle(fontSize: 16)),
              pw.Text('เลขงาน ${job['jobId']}'),
              if ('${job['pickupLabel']}'.isNotEmpty)
                pw.Text('นัดรับ ${job['pickupLabel']} (เวลาไทย)'),
              if ('${job['customerName']}'.isNotEmpty)
                pw.Text('${job['customerName']}'),
              pw.Divider(),
              for (final line in job['lines'] as List)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('${line['name']} × ${line['quantity']}',
                              style: const pw.TextStyle(fontSize: 14)),
                          if ('${line['note']}'.isNotEmpty)
                            pw.Text('${line['note']}'),
                        ])),
              pw.Divider(),
              pw.Text('ใบงานเตรียมอาหาร ไม่ใช่ใบเสร็จ'),
            ]));
    return pdf.save();
  }

  static Future<Uint8List> _buildBluetoothTicket(Map job, int paperMm) async {
    if (![58, 80].contains(paperMm)) throw ArgumentError('paperMm');
    final format =
        paperMm == 80 ? ReceiptGenerator.slip80 : ReceiptGenerator.slip58;
    final renderer = ReceiptTextRenderer();
    final content = <pw.Widget>[];
    Future<void> line(String text, {double size = 10}) async {
      content.add(await renderer.text(text,
          maxWidth: format.availableWidth,
          style: pw.TextStyle(fontSize: size)));
    }

    if (job['reprint'] == true) {
      await line('สำเนา / พิมพ์ซ้ำ — ตรวจใบเดิมก่อนทำอาหาร');
    }
    await line('ใบงานครัว • ${job['title'] ?? ''}', size: 14);
    await line('เลขงาน ${job['jobId'] ?? ''}');
    if ((job['pickupLabel'] ?? '').toString().isNotEmpty) {
      await line('นัดรับ ${job['pickupLabel']} (เวลาไทย)');
    }
    if ((job['customerName'] ?? '').toString().isNotEmpty) {
      await line('${job['customerName']}');
    }
    content.add(pw.Divider());
    for (final item in job['lines'] as List) {
      await line('${item['name']} × ${item['quantity']}', size: 12);
      if ((item['note'] ?? '').toString().isNotEmpty) {
        await line('${item['note']}');
      }
      content.add(pw.SizedBox(height: 6));
    }
    content.add(pw.Divider());
    await line('ใบงานเตรียมอาหาร ไม่ใช่ใบเสร็จ');
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

  static Future<void> printOrder(BuildContext context,
      {required String source,
      required String orderId,
      bool reprint = false}) async {
    BluetoothPrinterConfig? bluetooth;
    if (BluetoothPrinterService.supported) {
      final route = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
                title: const Text('พิมพ์ใบงานครัวด้วย'),
                children: [
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'bluetooth'),
                      child: const Text('เครื่องพิมพ์ Bluetooth')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, 'system'),
                      child: const Text('ระบบพิมพ์ของมือถือ / RawBT')),
                  SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ยกเลิก')),
                ],
              ));
      if (route == null || !context.mounted) return;
      if (route == 'bluetooth') {
        try {
          bluetooth = await BluetoothPrinterService.saved();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(BluetoothPrinterService.errorMessage(e))));
          }
          return;
        }
        if (!context.mounted) return;
        bluetooth ??= await Navigator.push<BluetoothPrinterConfig>(context,
            MaterialPageRoute(builder: (_) => const BluetoothPrinterScreen()));
        if (bluetooth == null || !context.mounted) return;
      }
    }
    Map? job;
    await performShopOperation(context, () async {
      job = Map.from(await _call('claimKitchenPrint',
          {'source': source, 'orderId': orderId, 'reprint': reprint}) as Map);
    }, success: 'ตรวจคิวพิมพ์แล้ว');
    if (job == null || !context.mounted) return;
    if (job!['alreadyPrinted'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('พิมพ์รายการทั้งหมดแล้ว ไม่มีรายการใหม่')));
      return;
    }
    var received = false;
    try {
      final bytes = await buildTicket(job!, paperMm: bluetooth?.paperMm);
      final bool sent;
      if (bluetooth != null) {
        await BluetoothPrinterService.printPdf(bytes, bluetooth);
        sent = true;
      } else {
        sent = await Printing.layoutPdf(
            onLayout: (_) => Future.value(bytes),
            name: 'kitchen_$orderId',
            format:
                PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm));
      }
      if (sent && context.mounted) {
        received = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                      title: const Text('ได้รับใบงานที่ครัวแล้วหรือยัง?'),
                      content: const Text(
                          'ตรวจว่ากระดาษออกครบก่อนยืนยัน หากยังไม่ออก งานจะคงรอตรวจสอบเพื่อพิมพ์ใหม่'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('ยังไม่ได้รับ')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('ได้รับครบแล้ว'))
                      ],
                    )) ??
            false;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(BluetoothPrinterService.errorMessage(e))));
      }
    } finally {
      if (context.mounted) {
        await performShopOperation(context, () async {
          await _call('finishKitchenPrint', {
            'jobId': job!['jobId'],
            'attempt': job!['attempt'],
            'received': received
          });
        },
            success:
                received ? 'ยืนยันใบงานครัวแล้ว' : 'งานยังรอพิมพ์ / ตรวจสอบ');
      }
    }
  }
}
