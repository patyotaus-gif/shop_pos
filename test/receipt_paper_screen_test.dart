import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shop_pos/models/receipt_profile.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/sale_receipt_screen.dart';
import 'package:shop_pos/utils/receipt_generator.dart';

class _PreviewPlatform extends PrintingPlatform {
  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canPrint: false, canShare: false, canRaster: true);
  @override
  Stream<PdfRaster> raster(Uint8List document, List<int>? pages, double dpi) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('receipt paper selector changes the preview and keeps sale total',
      (tester) async {
    final previous = PrintingPlatform.instance;
    PrintingPlatform.instance = _PreviewPlatform();
    addTearDown(() => PrintingPlatform.instance = previous);
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sale = Sale(
        id: 'paper-test',
        items: const [
          SaleItem(
              productId: 'cookie',
              productName: 'คุกกี้',
              price: 25,
              quantity: 1,
              subtotal: 25)
        ],
        total: 25,
        discount: 0,
        paid: 25,
        change: 0,
        createdAt: DateTime(2026, 10, 11),
        receiptProfile: const ReceiptProfile(name: 'ร้านทดสอบ'));
    await tester.pumpWidget(MaterialApp(home: SaleReceiptScreen(sale: sale)));
    await tester.pump();
    expect(tester.widget<PdfPreview>(find.byType(PdfPreview)).initialPageFormat,
        ReceiptGenerator.slip58);
    for (final entry in {
      'สลิป 80 มม.': ReceiptGenerator.slip80,
      'A4': PdfPageFormat.a4
    }.entries) {
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(entry.key).last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          tester.widget<PdfPreview>(find.byType(PdfPreview)).initialPageFormat,
          entry.value);
      expect(find.textContaining('ยอดรวม ฿25.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
