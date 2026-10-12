import 'package:flutter/material.dart';

/// Informational until merchant onboarding and live settlement are available.
/// Shop-editable settings must never activate a payment gateway.
class OnlinePaymentReadiness extends StatelessWidget {
  const OnlinePaymentReadiness({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ช่องทางเพิ่มเติมสำหรับลิงก์สั่งสินค้า',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            const _PaymentMethod(
                icon: Icons.credit_card, title: 'บัตรเครดิต / เดบิต'),
            const SizedBox(height: 12),
            const _PaymentMethod(
                icon: Icons.account_balance_wallet_outlined,
                title: 'TrueMoney'),
            const SizedBox(height: 16),
            const Text(
                'กำลังเตรียมบริการรับชำระเงิน ร้านยังเปิดใช้สองช่องทางนี้ไม่ได้ '
                'เมื่อบริการพร้อม จะแจ้งขั้นตอนสมัครและยืนยันข้อมูลร้านก่อนเปิดรับเงิน'),
            const SizedBox(height: 8),
            Text('ลูกค้ายังชำระผ่าน PromptPay ที่ร้านตั้งค่าไว้ได้ตามเดิม',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethod extends StatelessWidget {
  const _PaymentMethod({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const Text('รอเปิดบริการ • ยังรับชำระไม่ได้'),
              ],
            ),
          ),
        ],
      );
}
