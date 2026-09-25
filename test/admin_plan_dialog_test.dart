import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/admin_plan_dialog.dart';

void main() {
  testWidgets(
      'prefills current plan, requires reason and sends no expiry changes',
      (tester) async {
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => AdminPlanDialog(
                              shop: const {
                                'id': 'shop',
                                'name': 'ร้านทดสอบ',
                                'email': 'shop@example.com',
                                'tier': 'lite',
                                'plan': 'yearly',
                                'locations': 3
                              },
                              save: (data) async {
                                saved = data;
                              },
                            )),
                    child: const Text('เปิด'))))));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันเปลี่ยนแผน'));
    await tester.pumpAndSettle();
    expect(find.text('กรุณาระบุเหตุผล'), findsOneWidget);
    expect(saved, isNull);
    await tester.enterText(find.byType(TextFormField).last, 'ปรับตามคำขอร้าน');
    await tester.tap(find.text('ยืนยันเปลี่ยนแผน'));
    await tester.pumpAndSettle();
    expect(saved!['tier'], 'lite');
    expect(saved!['billingCycle'], 'yearly');
    expect(saved!['locations'], 3);
    expect(saved!['expected'], {
      'tier': 'lite',
      'shopType': 'retail',
      'plan': 'yearly',
      'locations': 3
    });
    expect(saved!['shopType'], 'retail');
    expect(saved!.containsKey('days'), isFalse);
    expect(saved!.containsKey('subscriptionEndsAt'), isFalse);
    expect(find.text('แก้แผนผู้ใช้'), findsNothing);
  });
}
