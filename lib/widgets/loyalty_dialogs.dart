import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../services/customer_service.dart';

/// Find or create a loyalty customer by phone.
Future<Customer?> showLoyaltyCustomerDialog(BuildContext context) async {
  final phone = TextEditingController(), name = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ลูกค้าสะสมแต้ม'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: phone,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
              labelText: 'เบอร์โทร', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          decoration: const InputDecoration(
              labelText: 'ชื่อ (ถ้าเป็นลูกค้าใหม่)',
              border: OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เลือก')),
      ],
    ),
  );
  if (ok != true || phone.text.trim().isEmpty) return null;
  return CustomerService.ensure(phone: phone.text, name: name.text);
}

/// Ask how many whole baht of points to use. Returns 0 to stop using points,
/// or null when cancelled.
Future<int?> showRedeemPointsDialog(BuildContext context,
    {required int maxBaht,
    required int pointsPerBaht,
    required int points,
    int current = 0}) {
  final ctrl =
      TextEditingController(text: '${current > 0 ? current : maxBaht}');
  return showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ใช้แต้มเป็นส่วนลด'),
      content: TextField(
        key: const ValueKey('redeem-baht'),
        controller: ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: 'ลดกี่บาท',
          prefixText: '฿',
          helperText:
              'ใช้ได้สูงสุด ฿$maxBaht · $pointsPerBaht แต้ม = ฿1 · มี $points แต้ม',
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        if (current > 0)
          TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('ไม่ใช้แต้ม')),
        FilledButton(
            key: const ValueKey('redeem-confirm'),
            onPressed: () {
              final baht = int.tryParse(ctrl.text.trim());
              if (baht == null || baht < 1 || baht > maxBaht) return;
              Navigator.pop(ctx, baht);
            },
            child: const Text('ใช้แต้ม')),
      ],
    ),
  );
}
