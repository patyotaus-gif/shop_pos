import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_saver/file_saver.dart';
import '../models/sale.dart';
import '../services/shop_database.dart';
import '../utils/receipt_generator.dart';
import '../services/auth_service.dart';
import '../services/sale_service.dart';
import '../widgets/refund_reason_dialog.dart';
import '../widgets/shop_operation.dart';

/// A completed payment stays visible even if the table stream closes its tab.
class SaleReceiptScreen extends StatefulWidget {
  const SaleReceiptScreen(
      {super.key,
      this.sale,
      this.saleId,
      this.loadSale,
      this.allowRefund = false})
      : assert(sale != null || saleId != null || loadSale != null);
  final Future<Sale> Function()? loadSale;
  final Sale? sale;
  final String? saleId;
  final bool allowRefund;
  @override
  State<SaleReceiptScreen> createState() => _SaleReceiptScreenState();
}

class _SaleReceiptScreenState extends State<SaleReceiptScreen> {
  bool _saving = false;
  String _paper = ReceiptGenerator.paperFormats.keys.first;
  Future<void> _saveFile(Sale sale) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await ReceiptGenerator.buildReceipt(sale,
          format: ReceiptGenerator.paperFormats[_paper]);
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
      appBar: AppBar(
          title: Text(widget.allowRefund
              ? 'บิลที่เชื่อมกับออเดอร์'
              : 'บันทึกการขายสำเร็จ')),
      body: FutureBuilder<Sale>(
          future: _sale,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.allowRefund
                    ? 'โหลดบิลที่เชื่อมกับออเดอร์ไม่สำเร็จ'
                    : 'บันทึกการขายแล้ว แต่โหลดใบเสร็จไม่สำเร็จ'),
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
              if (widget.allowRefund && !AuthService.isStaff)
                sale.isRefunded
                    ? const Text('คืนเงินบิลนี้แล้ว')
                    : TextButton.icon(
                        icon: const Icon(Icons.undo),
                        label: const Text('คืนเงินบิลนี้'),
                        onPressed: () async {
                          final reason = await showDialog<RefundDecision>(
                              context: context,
                              builder: (_) => RefundReasonDialog(
                                  amount: sale.total.toStringAsFixed(2),
                                  online: sale.paymentMethod ==
                                      PaymentMethod.online,
                                  debt: sale.isDebt));
                          if (reason == null || !context.mounted) return;
                          final ok = await performShopOperation(
                              context,
                              () => SaleService.refundSale(sale,
                                  reason: reason.reason,
                                  returnToStock: reason.returnToStock,
                                  refundMethod: reason.method),
                              success: 'บันทึกคืนเงินแล้ว');
                          if (ok && mounted) {
                            setState(() {
                              _sale = _load();
                              _sale.ignore();
                            });
                          }
                        }),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _paper,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'ขนาดกระดาษใบเสร็จ'),
                    items: ReceiptGenerator.paperFormats.keys
                        .map((name) =>
                            DropdownMenuItem(value: name, child: Text(name)))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _paper = value);
                          },
                  )),
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
                      key: ValueKey(_paper),
                      initialPageFormat: ReceiptGenerator.paperFormats[_paper],
                      pageFormats: ReceiptGenerator.paperFormats,
                      build: (format) =>
                          ReceiptGenerator.buildReceipt(sale, format: format),
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
                          child: Text(
                              widget.allowRefund ? 'กลับออเดอร์' : 'ขายต่อ')))),
            ]);
          }));
}
