import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/compact_action.dart';
import 'package:shop_pos/widgets/content_width.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(800, 1100),
    const Size(1480, 924),
  ]) {
    testWidgets('single-column actions fit and scroll at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: const TextScaler.linear(2)),
          child: Scaffold(
            body: Row(children: [
              if (size.width > 1000) const SizedBox(width: 192),
              Expanded(
                child: ContentWidth(
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    ActionButtons(children: [
                      OutlinedButton.icon(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.copy),
                        label: const Text('คัดลอกลิงก์'),
                      ),
                      FilledButton.icon(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.share),
                        label: const Text('แชร์ลิงก์'),
                      ),
                    ]),
                    CompactAction(
                      child: OutlinedButton.icon(
                        onPressed: () => taps++,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('ตรวจรายการที่ยอดอาจไม่ตรงกัน'),
                      ),
                    ),
                    const SizedBox(height: 1400),
                    CompactAction(
                      child: FilledButton(
                        onPressed: () => taps++,
                        child: const Text('บันทึก'),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ));
      final page = tester.getRect(find.byType(ListView));
      final left = size.width > 1000 ? 192.0 : 0.0;
      expect(page.width, lessThanOrEqualTo(840));
      expect(page.center.dx, closeTo(left + (size.width - left) / 2, .01));
      if (size.width <= 840) expect(page.width, size.width);
      for (final label in [
        'คัดลอกลิงก์',
        'แชร์ลิงก์',
        'ตรวจรายการที่ยอดอาจไม่ตรงกัน',
        'บันทึก',
      ]) {
        final button = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        await tester.scrollUntilVisible(button, 250);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final rect = tester.getRect(button);
        expect(rect.width, lessThanOrEqualTo(360));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.left, greaterThanOrEqualTo(page.left + 16));
        expect(rect.right, lessThanOrEqualTo(page.right - 16));
        await tester.tap(button);
      }
      expect(taps, 4);
      expect(tester.takeException(), isNull);
    });
  }
}
