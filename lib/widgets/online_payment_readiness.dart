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
            Text('รับชำระออนไลน์ผ่าน Omise',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text('บริการเสริมฟรี ไม่มีค่าแพ็กเกจรายเดือนจาก Pokpok '
                'ร้านค้ารับผิดชอบค่าธรรมเนียมธุรกรรมตามเงื่อนไขของ Omise'),
            const SizedBox(height: 12),
            const _PaymentMethod(
                icon: Icons.credit_card, title: 'บัตรเครดิต / เดบิต'),
            const SizedBox(height: 12),
            const _PaymentMethod(
                icon: Icons.qr_code_2, title: 'พร้อมเพย์'),
            const SizedBox(height: 12),
            const _PaymentMethod(
                icon: Icons.account_balance_wallet_outlined,
                title: 'TrueMoney'),
            const SizedBox(height: 16),
            const Text(
                'ขณะนี้อยู่ระหว่างทดสอบ ยังเปิดรับเงินจริงผ่าน Omise ไม่ได้ '
                'เมื่อบริการพร้อม เจ้าของร้านจะเลือกเปิดใช้ได้หลังเชื่อมบัญชีและยืนยันข้อมูลกับ Omise สำเร็จ'),
            const SizedBox(height: 8),
            Text('หน้าร้านใช้เงินสดและเงินโอนได้ตามปกติ '
                'ส่วน QR สำหรับลิงก์สั่งสินค้าเดิมยังใช้การตั้งค่า PromptPay ด้านล่าง',
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
