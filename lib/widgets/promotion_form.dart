import 'package:flutter/material.dart';

/// Labels live outside the input so Thai text can wrap at large text scales.
/// Use the app theme for input borders, typography and colors.
class PromotionField extends StatelessWidget {
  const PromotionField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Semantics(label: label, child: child),
          ],
        ),
      );
}

class PromotionSummary extends StatelessWidget {
  const PromotionSummary({super.key, required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            Text('สรุปก่อนบันทึก',
                style: Theme.of(context).textTheme.titleSmall),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(line),
              ),
          ],
        ),
      );
}

/// An illustrative calculation, not a quote for the current form or cart.
class PromotionCalculationExample extends StatelessWidget {
  const PromotionCalculationExample({super.key});

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('ตัวอย่างการใช้โปรโมชั่นร่วมกัน'),
        children: const [
          Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'ตัวอย่างสำหรับบิลโต๊ะหรือลิงก์สั่งซื้อ\n'
              'สินค้าราคาปกติรวม 120 บาท\n'
              'หลังลดรายสินค้า เหลือ 100 บาท\n'
              'ใช้ราคาชุด 80 บาท ลดเพิ่ม 20 บาท\n'
              'ใช้คูปอง 10% ของ 80 บาท ลดเพิ่ม 8 บาท\n'
              'ยอดสินค้าเหลือ 72 บาท\n\n'
              'ของแถมราคา 0 บาท แต่ตัดสต็อกตามจำนวนจริง '
              'ตัวอย่างนี้สมมติว่าเข้าเงื่อนไขทุกโปรโมชั่น '
              'ยังไม่รวมค่าจัดส่งหรือค่าใช้จ่ายอื่น',
            ),
          ),
        ],
      );
}
