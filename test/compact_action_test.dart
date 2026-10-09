import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/compact_action.dart';
import 'package:shop_pos/widgets/settings_sections.dart';

void main() {
  for (final width in [320.0, 568.0, 1280.0]) {
    testWidgets('actions fit width $width with enlarged Thai text',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(width, 800), textScaler: const TextScaler.linear(2)),
          child: Scaffold(
              body: ListView(padding: const EdgeInsets.all(16), children: [
            CompactAction(
                child: FilledButton(
                    onPressed: () => taps++, child: const Text('บันทึก'))),
            CompactAction(
                primary: true,
                child: FilledButton(
                    onPressed: () => taps++,
                    child: const Text('ยืนยันการชำระเงิน'))),
            ActionButtons(children: [
              OutlinedButton.icon(
                  onPressed: () => taps++,
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มสินค้า')),
              FilledButton.icon(
                  onPressed: () => taps++,
                  icon: const Icon(Icons.soup_kitchen),
                  label: const Text('ส่งครัว (12)')),
              FilledButton(onPressed: null, child: const Text('ปิดบิล')),
            ]),
          ])),
        ),
      ));
      await tester.pumpAndSettle();
      final buttons = find.byWidgetPredicate((w) => w is ButtonStyleButton);
      final rects = <Rect>[];
      for (final element in buttons.evaluate()) {
        final finder = find.byWidget(element.widget);
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final rect = tester.getRect(finder);
        expect(rect.width, lessThanOrEqualTo(360));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.left, greaterThanOrEqualTo(16));
        expect(rect.right, lessThanOrEqualTo(width - 16));
        rects.add(rect);
        await tester.tap(finder);
      }
      expect(taps, 4);
      expect(tester.takeException(), isNull);
      if (width == 1280) {
        expect(rects[0].width, lessThan(250));
        expect(rects[1].width, 360);
        expect(rects[2].center.dy, rects[3].center.dy);
      } else if (width == 320) {
        expect(rects[3].top, greaterThan(rects[2].bottom));
      }
    });
  }

  testWidgets('tablet settings actions use their label width', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: SettingsSections(sections: [
          SettingsSection(title: 'ข้อมูลร้าน', icon: Icons.store, children: [
            FilledButton(
                onPressed: () => saved = true, child: const Text('บันทึก')),
          ]),
        ]))));
    expect(tester.getSize(find.byType(FilledButton)).width, lessThan(200));
    await tester.tap(find.text('บันทึก'));
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
