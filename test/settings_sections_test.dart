import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/settings_sections.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(PokpokTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf')))
        .load();
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'selected settings tab respects large text and reduced motion at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2), disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
            body: SettingsSections(sections: [
          SettingsSection(title: 'ข้อมูลร้าน', icon: Icons.store, children: []),
          SettingsSection(
              title: 'พนักงานและการจัดการ',
              icon: Icons.people,
              children: [
                SettingsHeading('ลูกค้าสะสมแต้ม', helper: 'จัดการสมาชิกของร้าน')
              ]),
        ])),
      ));
      final tab = find.widgetWithText(ChoiceChip, 'พนักงานและการจัดการ');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(tab).selected, isTrue);
      final indicator = tester.widget<AnimatedScale>(
          find.descendant(of: tab, matching: find.byType(AnimatedScale)));
      expect(indicator.duration, Duration.zero);
      expect(indicator.scale, 1);
      expect(find.text('ลูกค้าสะสมแต้ม').hitTestable(), findsOneWidget);
      expect(find.text('จัดการสมาชิกของร้าน').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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
