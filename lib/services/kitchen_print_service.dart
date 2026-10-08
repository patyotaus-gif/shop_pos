import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'auth_service.dart';
import '../widgets/shop_operation.dart';

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
          .httpsCallable(name)
          .call({'shopId': AuthService.shopId, ...data}).then((r) => r.data);

  static Future<Uint8List> buildTicket(Map job) async {
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

  static Future<void> printOrder(BuildContext context,
      {required String source,
      required String orderId,
      bool reprint = false}) async {
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
      final bytes = await buildTicket(job!);
      final sent = await Printing.layoutPdf(
          onLayout: (_) => Future.value(bytes),
          name: 'kitchen_$orderId',
          format: PdfPageFormat(80 * PdfPageFormat.mm, 297 * PdfPageFormat.mm));
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
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('พิมพ์ไม่สำเร็จ ตรวจเครื่องพิมพ์แล้วลองใหม่')));
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
