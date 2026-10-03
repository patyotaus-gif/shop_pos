import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/settings_sections.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 800)]) {
    testWidgets('settings sections navigate without overflow at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SettingsSections(sections: [
        SettingsSection(
            title: 'ข้อมูลร้าน',
            icon: Icons.store,
            children: [TextField(controller: controller)]),
        const SettingsSection(
            title: 'บัญชีและแพ็กเกจ',
            icon: Icons.person,
            children: [Text('เชื่อมบัญชี')]),
      ]))));
      await tester.enterText(find.byType(TextField), 'My shop');
      await tester.tap(find.text('บัญชีและแพ็กเกจ'));
      await tester.pumpAndSettle();
      expect(find.text('เชื่อมบัญชี'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('ข้อมูลร้าน'));
      await tester.pumpAndSettle();
      expect(find.text('My shop'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
