import 'package:flutter/material.dart';
import '../models/sale.dart';

class RefundDecision {
  const RefundDecision(this.reason, this.returnToStock, this.method);
  final String reason;
  final bool returnToStock;
  final PaymentMethod method;
}

class RefundReasonDialog extends StatefulWidget {
  const RefundReasonDialog(
      {super.key,
      required this.amount,
      required this.online,
      this.debt = false});
  final String amount;
  final bool online;
  final bool debt;
  @override
  State<RefundReasonDialog> createState() => _RefundReasonDialogState();
}

class _RefundReasonDialogState extends State<RefundReasonDialog> {
  String? _reason;
  bool _returnToStock = false;
  PaymentMethod _method = PaymentMethod.cash;
  final _other = TextEditingController();
  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason == 'อื่น ๆ' ? _other.text.trim() : _reason;
    return AlertDialog(
      title: const Text('คืนเงินบิลที่ชำระแล้ว'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('ยอด ฿${widget.amount}'),
        const Text(
            'บิลนี้รับชำระแล้ว การคืนเงินจะบันทึกประวัติไว้ ไม่ลบบิลเดิม'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'เหตุผลที่คืนเงิน'),
          items: [
            'บันทึกรายการผิด',
            'ลูกค้ายกเลิกหลังชำระ',
            'สินค้า / อาหารมีปัญหา',
            'อื่น ๆ'
          ]
              .map((text) => DropdownMenuItem(value: text, child: Text(text)))
              .toList(),
          onChanged: (value) => setState(() => _reason = value),
        ),
        if (_reason == 'อื่น ๆ')
          TextField(
            controller: _other,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'ระบุเหตุผล'),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _returnToStock,
          title: const Text('คืนสินค้า / วัตถุดิบเข้าสต็อก'),
          subtitle: const Text('เลือกเฉพาะของที่ยังนำกลับไปขายหรือใช้ได้'),
          onChanged: (value) => setState(() => _returnToStock = value ?? false),
        ),
        if (widget.debt) ...[
          const Text('ยกเลิกหนี้คงค้าง และคืนเฉพาะเงินที่รับชำระแล้ว'),
          DropdownButtonFormField<PaymentMethod>(
            initialValue: _method,
            decoration: const InputDecoration(
                labelText: 'ช่องทางคืนเงินที่รับชำระหนี้'),
            items: [
              PaymentMethod.cash,
              PaymentMethod.transfer,
              PaymentMethod.qr
            ]
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (m) => setState(() => _method = m ?? PaymentMethod.cash),
          ),
        ],
        Text(widget.online
            ? 'ระบบจะส่งคำขอคืนเงินผ่านผู้ให้บริการชำระเงิน'
            : 'การบันทึกนี้ไม่โอนเงินคืนอัตโนมัติ โปรดคืนเงินให้ลูกค้าตามช่องทางที่รับชำระ'),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('กลับ')),
        FilledButton(
          onPressed: reason == null || reason.isEmpty
              ? null
              : () => Navigator.pop(
                  context, RefundDecision(reason, _returnToStock, _method)),
          child: const Text('ยืนยันคืนเงิน'),
        ),
      ],
    );
  }
}
