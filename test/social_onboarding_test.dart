import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/register_screen.dart';

void main() {
  testWidgets(
      'authenticated onboarding collects shop details without requesting a password',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: RegisterScreen(completeProfile: true)));
    expect(find.text('ตั้งค่าร้านของคุณ'), findsOneWidget);
    expect(find.text('ข้อมูลบัญชี'), findsNothing);
    expect(find.text('รหัสผ่าน'), findsNothing);
    expect(find.text('ดำเนินการต่อด้วย Google'), findsNothing);
    expect(find.text('ร้านค้าปลีก'), findsOneWidget);
    expect(find.text('ร้านอาหาร'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'My shop');
    final submit = find.text('สมัครและเริ่มใช้งานฟรี');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('กรุณายอมรับเงื่อนไขการใช้บริการและนโยบายความเป็นส่วนตัว'),
        findsOneWidget);
  });
  testWidgets(
      'signup chooses account first and preserves email when going back',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    expect(find.text('ดำเนินการต่อด้วย Google'), findsOneWidget);
    expect(find.text('ดำเนินการต่อด้วย Apple'), findsOneWidget);
    expect(find.text('ชื่อร้าน'), findsNothing);
    expect(find.text('อีเมล'), findsNothing);
    await tester.tap(find.text('สมัครด้วยอีเมล'));
    await tester.pumpAndSettle();
    expect(find.text('อีเมล'), findsOneWidget);
    expect(find.text('ยืนยันรหัสผ่าน'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'owner@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'example123');
    await tester.enterText(find.byType(TextFormField).at(2), 'example123');
    await tester.ensureVisible(find.text('ถัดไป: ตั้งค่าร้าน'));
    await tester.tap(find.text('ถัดไป: ตั้งค่าร้าน'));
    await tester.pumpAndSettle();
    expect(find.text('ชื่อร้าน'), findsOneWidget);
    expect(find.text('รหัสผ่าน'), findsNothing);
    await tester.tap(find.text('กลับไปแก้ไขบัญชี'));
    await tester.pumpAndSettle();
    expect(find.text('owner@example.com'), findsOneWidget);
  });
}
