import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cash_session.dart';
import 'package:shop_pos/widgets/cash_reconciliation_dialog.dart';

void main() {
  test('closing snapshot preserves included opening cash and reviewed count',
      () {
    final result = SessionSummary.fromMap({
      'openingCashIncluded': -70,
      'reconciledCount': 2,
      'expectedCash': 500,
    });
    expect(SessionSummary.fromMap(result.toMap()).openingCashIncluded, -70);
    expect(result.reconciledCount, 2);
    expect(result.expectedCash, 500);
    expect(SessionSummary.fromMap({}).openingCashIncluded, 0);
  });

  testWidgets(
      'cash needs explicit drawer choice and reason; retry cannot submit twice',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    String? chosen;
    final done = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => CashReconciliationDialog(
                            movementId: 'sale-brownie',
                            amountMinor: 7000,
                            method: 'cash',
                            kind: 'sale',
                            openedAt: DateTime(2026, 10, 10),
                            openingFloat: 500,
                            save: (reason, treatment) {
                              calls++;
                              chosen = treatment;
                              return done.future;
                            })),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'ยืนยันจัดเข้ารอบ'))
            .onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'ตรวจสลิปแล้ว');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รวมแล้ว · ไม่นับเงินสดซ้ำ').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ยืนยันจัดเข้ารอบ'));
    await tester.tap(find.text('ยืนยันจัดเข้ารอบ'));
    await tester.pump();
    expect(calls, 1);
    expect(chosen, 'includedInOpeningFloat');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CashReconciliationDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('noncash failure remains reviewable and can retry same entry',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: CashReconciliationDialog(
            movementId: 'sale-qr',
            amountMinor: 7091,
            method: 'qr',
            kind: 'sale',
            openedAt: DateTime(2026, 10, 10),
            openingFloat: 0,
            save: (_, treatment) async {
              calls++;
              expect(treatment, 'nonCash');
              throw StateError('ลองรายการเดิมอีกครั้ง');
            })));
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.enterText(find.byType(TextField), 'ตรวจสลิปแล้ว');
    await tester.pump();
    await tester.tap(find.text('ยืนยันจัดเข้ารอบ'));
    await tester.pumpAndSettle();
    expect(find.text('ลองรายการเดิมอีกครั้ง'), findsOneWidget);
    await tester.tap(find.text('ยืนยันจัดเข้ารอบ'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
