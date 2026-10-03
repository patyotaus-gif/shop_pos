import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/line_service.dart';
import 'package:shop_pos/widgets/safe_detail_sheet.dart';
import 'package:shop_pos/widgets/refund_reason_dialog.dart';
import 'package:shop_pos/widgets/workspace_sections.dart';

void main() {
  test('LINE test rejects false, skipped and malformed responses', () {
    for (final value in [
      null,
      {},
      {'success': false},
      {'skipped': true}
    ]) {
      expect(() => LineService.requireAccepted(value), throwsStateError);
    }
    expect(
        () => LineService.requireAccepted({'success': true}), returnsNormally);
    expect(LineService.isValidUserId('ordinary.line.name'), isFalse);
    expect(LineService.isValidUserId('U${'a' * 32}'), isTrue);
  });

  testWidgets('long bill scrolls to actions above Android system navigation',
      (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showSafeDetailSheet<void>(
                        context: context,
                        builder: (_) => Column(children: [
                              for (var i = 0; i < 60; i++) Text('Item $i'),
                              TextButton(
                                  onPressed: () {},
                                  child: const Text('Receipt action')),
                            ])),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Receipt action'), 250,
        scrollable: find.byType(Scrollable).last);
    expect(tester.getBottomRight(find.text('Receipt action')).dy,
        lessThanOrEqualTo(619));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refund needs a reason and Other needs text', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: RefundReasonDialog(amount: '100', online: false))));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อื่น ๆ').last);
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'ลูกค้าขอคืนสินค้า');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('grouped sections preserve unfinished input', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: WorkspaceSections(
                labels: ['Overview', 'Reports'],
                pages: [TextField(), Text('Report body')]))));
    await tester.enterText(find.byType(TextField), 'saved draft');
    await tester.tap(find.text('Reports'));
    await tester.pump();
    await tester.tap(find.text('Overview'));
    await tester.pump();
    expect(find.text('saved draft'), findsOneWidget);
  });
}
