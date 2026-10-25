import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/line_notification_settings.dart';
import 'package:shop_pos/widgets/settings_sections.dart';

void main() {
  for (final width in [320.0, 393.0, 800.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('LINE settings at width $width text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var saves = 0;
        await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
              body: SettingsSections(sections: [
            SettingsSection(
                title: 'การแจ้งเตือน',
                icon: Icons.notifications,
                children: [
                  LineNotificationSettings(
                      controller: controller,
                      enabled: true,
                      saving: false,
                      onEnabledChanged: (_) {},
                      onSave: () => saves++,
                      onTest: () {},
                      onOpenLine: () {}),
                ]),
            const SettingsSection(
                title: 'ร้าน',
                icon: Icons.store,
                children: [Text('ข้อมูลร้าน')])
          ])),
        ));
        await tester.tap(find.byType(ExpansionTile));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(
            find.byType(TextField), 'U0123456789abcdef0123456789abcdef');
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(TextField)).height, lessThan(200));
        await tester.ensureVisible(find.text('บันทึก'));
        await tester.tap(find.text('บันทึก'));
        expect(saves, 1);
        expect(tester.takeException(), isNull);
        // Re-entering restores expansion and field scroll state independently.
        final navigation = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        navigation.jumpTo(navigation.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'ร้าน'));
        await tester.pumpAndSettle();
        expect(find.text('ข้อมูลร้าน'), findsOneWidget);
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, 'การแจ้งเตือน'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(TextField), findsOneWidget);
        expect(controller.text, 'U0123456789abcdef0123456789abcdef');
        await tester.ensureVisible(
            find.text('ตั้งค่าการแจ้งเตือน / เชื่อมด้วยรหัสเอง'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ตั้งค่าการแจ้งเตือน / เชื่อมด้วยรหัสเอง'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
            find.text('ตั้งค่าการแจ้งเตือน / เชื่อมด้วยรหัสเอง'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ตั้งค่าการแจ้งเตือน / เชื่อมด้วยรหัสเอง'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(TextField)).height, lessThan(200));
      });
    }
  }
}
