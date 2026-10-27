import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/owner_pin_screen.dart';

void main() {
  testWidgets('setup requires matching masked six-digit PIN, small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? saved;
    await tester.pumpWidget(MaterialApp(
        home: OwnerPinScreen(setup: true, submit: (pin) async => saved = pin)));
    expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((f) => f.obscureText),
        isTrue);
    await tester.enterText(find.byType(TextField).at(0), '827364');
    await tester.enterText(find.byType(TextField).at(1), '111111');
    await tester.ensureVisible(find.text('บันทึก PIN'));
    await tester.tap(find.text('บันทึก PIN'));
    await tester.pump();
    expect(saved, isNull);
    expect(find.text('PIN ทั้งสองช่องไม่ตรงกัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong PIN stays locked and explains server lockout',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: OwnerPinScreen(submit: (_) async {
      throw FirebaseFunctionsException(
          code: 'resource-exhausted', message: 'รอ 15 นาที');
    })));
    await tester.enterText(find.byType(TextField), '827364');
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าโหมดเจ้าของ'));
    await tester.pumpAndSettle();
    expect(find.text('รอ 15 นาที'), findsOneWidget);
    expect(find.text('ลืม PIN / ใช้บัญชีเจ้าของแทน'), findsOneWidget);
  });

  testWidgets(
      'owner returns only after successful authentication; cancel and fallback differ',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  OwnerPinScreen(submit: (_) async {})));
                    },
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลืม PIN / ใช้บัญชีเจ้าของแทน'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '827364');
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าโหมดเจ้าของ'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
