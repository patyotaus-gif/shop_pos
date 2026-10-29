import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/user_switch_screen.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform staff PIN works with long name and landscape keyboard',
        (tester) async {
      tester.view.physicalSize = const Size(568, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      String? submitted;
      const name = 'พนักงานทดสอบสาขาศรีสะเกษ กะเช้าประจำร้าน';
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.5)),
          child: child!,
        ),
        home: UserSwitchScreen(
          loadStaff: () async => {
            'staff': [
              {'id': 'a', 'name': name}
            ]
          },
          switchTo: (_, pin) async => submitted = pin,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(name), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(name));
      tester.view.viewInsets = const FakeViewPadding(bottom: 140);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '123456');
      await tester.ensureVisible(find.text('เข้าใช้งาน'));
      await tester.tap(find.text('เข้าใช้งาน'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(submitted, '123456');
      expect(tester.takeException(), isNull);
    });
  }
}
