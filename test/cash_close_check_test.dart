import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cash_close_check.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/cash_close_blockers_dialog.dart';

void main() {
  test('missing or contradictory readiness cannot enable closing', () {
    for (final data in <Map<String, dynamic>>[
      {},
      {'canClose': true, 'closed': true},
      {'canClose': true, 'issueCount': 1},
      {
        'canClose': true,
        'issues': [
          {'type': 'pendingOrder'}
        ]
      },
    ]) {
      expect(CashCloseCheck.fromMap(data).canClose, isFalse);
    }
    expect(CashCloseCheck.fromMap({'canClose': true, 'issueCount': 0}).canClose,
        isTrue);
  });

  testWidgets(
      'blocked phone dialog scrolls and resolves an order destination without closing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CashCloseDestination? destination;
    final check = CashCloseCheck.fromMap({
      'canClose': false,
      'issueCount': 24,
      'futureOrderCount': 2,
      'issues': List.generate(
          20,
          (i) => {
                'type': 'pendingOrder',
                'id': 'order-$i',
                'label':
                    'ลูกค้าที่สั่งอาหารกลับบ้าน ชื่อยาวเพื่อทดสอบการตัดบรรทัด',
                'message': 'ออเดอร์ยังรอชำระ',
              }),
    });
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () async {
                      destination = await showDialog<CashCloseDestination>(
                          context: context,
                          builder: (_) =>
                              CashCloseBlockersDialog(check: check));
                    },
                    child: const Text('ตรวจปิดรอบ'),
                  ))),
    ));
    await tester.tap(find.text('ตรวจปิดรอบ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังปิดยอดไม่ได้'), findsOneWidget);
    expect(find.text('ปิดรอบ'), findsNothing);
    expect(find.textContaining('นัดรับวันถัดไป 2'), findsOneWidget);
    await tester.ensureVisible(find.text('ดูออเดอร์'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ดูออเดอร์'));
    await tester.pumpAndSettle();
    expect(destination, CashCloseDestination.orders);
  });

  testWidgets('an already closed session cannot start another count',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: CashCloseBlockersDialog(
      check: CashCloseCheck.fromMap({'closed': true, 'canClose': false}),
    )));
    expect(find.text('รอบนี้ปิดไปแล้ว'), findsOneWidget);
    expect(find.text('ดูออเดอร์'), findsNothing);
    expect(find.text('ปิดรอบ'), findsNothing);
  });
}
