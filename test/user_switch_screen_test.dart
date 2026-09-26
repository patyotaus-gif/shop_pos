import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/user_switch_screen.dart';

void main() {
  testWidgets(
      'choosing a cashier requires a masked PIN and submits to authentication',
      (tester) async {
    String? chosen, code;
    await tester.pumpWidget(MaterialApp(
        home: UserSwitchScreen(
      loadStaff: () async => {
        'staff': [
          {'id': 'a', 'name': 'พนักงาน A'}
        ]
      },
      switchTo: (id, pin) async {
        chosen = id;
        code = pin;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('เจ้าของร้าน'), findsOneWidget);
    await tester.tap(find.text('พนักงาน A'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('เข้าใช้งาน'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(chosen, 'a');
    expect(code, '123456');
  });
  testWidgets('staff directory failure never opens privileged menus',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: UserSwitchScreen(
            loadStaff: () async => throw StateError('offline'))));
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.text('รายงาน'), findsNothing);
    expect(find.text('ตั้งค่า'), findsNothing);
  });
}
