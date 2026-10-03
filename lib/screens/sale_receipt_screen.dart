import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_saver/file_saver.dart';
import '../models/sale.dart';
import '../services/shop_database.dart';
import '../utils/receipt_generator.dart';

/// A completed payment stays visible even if the table stream closes its tab.
class SaleReceiptScreen extends StatefulWidget {
  const SaleReceiptScreen({super.key, this.sale, this.saleId, this.loadSale})
      : assert(sale != null || saleId != null || loadSale != null);
  final Future<Sale> Function()? loadSale;
  final Sale? sale;
  final String? saleId;
  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  bool _saving = false;
  Future<void> _saveFile(Sale sale) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await ReceiptGenerator.buildReceipt(sale);
      final path = await FileSaver.instance.saveAs(
          name: 'receipt_${sale.receiptNo ?? sale.id}',
          bytes: bytes,
          fileExtension: 'pdf',
          mimeType: MimeType.pdf);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกใบเสร็จแล้ว')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('บันทึกไฟล์ไม่สำเร็จ ลองใหม่ได้โดยไม่ต้องรับเงินซ้ำ')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  late Future<Sale> _sale = _load();
  Future<Sale> _load() async {
    if (widget.loadSale != null) return widget.loadSale!();
    if (widget.sale != null) return widget.sale!;
    final doc =
        await ShopDatabase.shop.collection('sales').doc(widget.saleId).get();
    if (!doc.exists) throw StateError('ยังโหลดใบเสร็จไม่ได้');
    return Sale.fromFirestore(doc.data()!, doc.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('บันทึกการขายสำเร็จ')),
      body: FutureBuilder<Sale>(
          future: _sale,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('บันทึกการขายแล้ว แต่โหลดใบเสร็จไม่สำเร็จ'),
                const Text('ไม่ต้องรับเงินซ้ำ เปิดดูย้อนหลังในรายงานได้'),
                TextButton(
                    onPressed: () => setState(() {
                          _sale = _load();
                          // Observe fast failures until FutureBuilder subscribes next frame.
                          _sale.ignore();
                        }),
                    child: const Text('ลองโหลดใบเสร็จใหม่')),
              ]));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final sale = snapshot.data!;
            return Column(children: [
              TextButton.icon(
                  onPressed: _saving ? null : () => _saveFile(sale),
                  icon: const Icon(Icons.download),
                  label: Text(
                      _saving ? 'กำลังบันทึก...' : 'บันทึก PDF ลงเครื่อง')),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                      'ยอดรวม ฿${sale.total.toStringAsFixed(2)} · ${sale.paymentMethod.label}'
                      '${sale.paymentMethod == PaymentMethod.cash ? '\nเงินทอน ฿${sale.change.toStringAsFixed(2)}' : ''}',
                      textAlign: TextAlign.center)),
              Expanded(
                  child: PdfPreview(
                      build: (_) => ReceiptGenerator.buildReceipt(sale),
                      pdfFileName: 'receipt_${sale.receiptNo ?? sale.id}.pdf',
                      canChangeOrientation: false,
                      canChangePageFormat: false,
                      allowPrinting: true,
                      allowSharing: true)),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('ขายต่อ')))),
            ]);
          }));
}
