import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/compact_action.dart';
import 'package:shop_pos/widgets/document_workspace.dart';
import 'package:shop_pos/screens/table_form_screen.dart';
import 'package:shop_pos/screens/owner_pin_screen.dart';

void main() {
  for (final config in [
    (const Size(320, 568), 1.0, 0.0),
    (const Size(390, 740), 2.0, 250.0),
    (const Size(800, 1100), 1.0, 0.0),
    (const Size(1480, 924), 1.0, 0.0),
    (const Size(1480, 924), 2.0, 0.0),
    (const Size(740, 390), 1.0, 0.0),
  ]) {
    final (size, scale, keyboard) = config;
    testWidgets('document remains visible and tools reachable $config',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var actions = 0, continues = 0;
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: child!),
        home: Scaffold(
            appBar: AppBar(title: const Text('ใบเสร็จ')),
            body: DocumentWorkspace(
              controls: [
                const TextField(
                    decoration: InputDecoration(labelText: 'ขนาดกระดาษ')),
                const SizedBox(height: 400),
                FilledButton(
                    onPressed: () => actions++,
                    child: const Text('พิมพ์ใบเสร็จ')),
              ],
              preview:
                  const ColoredBox(key: Key('preview'), color: Colors.white),
              footer: CompactAction(
                  primary: true,
                  child: FilledButton(
                      onPressed: () => continues++,
                      child: const Text('ขายต่อ'))),
            )),
      ));
      final preview = tester.getRect(find.byKey(const Key('preview')));
      expect(preview.height, greaterThan(40));
      expect(preview.right, lessThanOrEqualTo(size.width));
      expect(preview.bottom, lessThanOrEqualTo(size.height - keyboard));
      final next = find.widgetWithText(FilledButton, 'ขายต่อ');
      expect(tester.getSize(next).width, lessThanOrEqualTo(360));
      expect(tester.getSize(next).height, greaterThanOrEqualTo(48));
      await tester.tap(next);
      await tester.scrollUntilVisible(find.text('พิมพ์ใบเสร็จ'), 150,
          scrollable: find.descendant(
              of: find.byType(ListView),
              matching: find.byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('พิมพ์ใบเสร็จ'));
      expect(actions, 1);
      expect(continues, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [const Size(320, 568), const Size(1480, 924)]) {
    testWidgets('forms constrain fields and keep validation reachable $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: const TableFormScreen()));
      expect(tester.getSize(find.byType(TextFormField).first).width,
          lessThanOrEqualTo(608));
      final save = find.widgetWithText(FilledButton, 'เพิ่มโต๊ะ');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getSize(save).width, lessThanOrEqualTo(360));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('กรุณากรอกชื่อโต๊ะ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: OwnerPinScreen(submit: (_) async {})));
      expect(
          tester.getSize(find.byType(TextField)).width, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
    });
  }
}
