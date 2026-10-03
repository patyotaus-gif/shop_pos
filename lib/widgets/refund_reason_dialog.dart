import 'package:flutter/material.dart';

class RefundReasonDialog extends StatefulWidget {
  const RefundReasonDialog(
      {super.key, required this.amount, required this.online});
  final String amount;
  final bool online;
  @override
  State<RefundReasonDialog> createState() => _RefundReasonDialogState();
}

class _RefundReasonDialogState extends State<RefundReasonDialog> {
  String? _reason;
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
              : () => Navigator.pop(context, reason),
          child: const Text('ยืนยันคืนเงิน'),
        ),
      ],
    );
  }
}
