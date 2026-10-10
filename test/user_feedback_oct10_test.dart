import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cash_session.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/report_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/widgets/cash_movement_dialog.dart';
import 'package:shop_pos/widgets/sales_insights.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

Widget app(Widget child) => MaterialApp(
      theme: PokpokTheme.light(),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

void main() {
  setUpAll(() async {
    final fonts = FontLoader(PokpokTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    await fonts.load();
  });
  testWidgets(
      'custom range opens in Thai, cancels and reopens without stuck barrier',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.collection('shops').doc('test');
    addTearDown(() => ShopDatabase.overrideShop = null);
    await ShopDatabase.overrideShop!.set({'name': 'test', 'tier': 'full'});
    await tester.pumpWidget(app(const ReportScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    await tester.tap(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    // Choose a real range through the calendar and save it.
    await tester.tap(find.text('1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('กำหนดเอง'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'legacy cash payment remains visible separately from unknown sales channel',
      (tester) async {
    final date = Timestamp.fromDate(DateTime(2026, 10, 10));
    final sales = [
      Sale.fromFirestore(
          {'createdAt': date, 'total': 485, 'paymentMethod': 'cash'}, 'cash'),
      Sale.fromFirestore({
        'createdAt': date,
        'total': 100,
        'paymentMethod': 'cash',
        'isDebt': true
      }, 'credit'),
      Sale.fromFirestore({
        'createdAt': date,
        'total': 44,
        'paymentMethod': 'cash',
        'isRefunded': true
      }, 'refund'),
    ];
    await tester.pumpWidget(app(Scaffold(body: SalesInsights(sales: sales))));
    await tester.pumpAndSettle();
    final cash =
        find.ancestor(of: find.text('เงินสด'), matching: find.byType(ListTile));
    expect(find.descendant(of: cash, matching: find.text('฿485.00')),
        findsOneWidget);
    expect(find.text('ขายเชื่อ'), findsOneWidget);
    expect(find.text('ช่องทางที่ลูกค้าสั่งซื้อ'), findsOneWidget);
    expect(find.text('ไม่ระบุช่องทาง'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cash entry validates reason and decimal amount, prevents double submit',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final done = Completer<void>();
    final calls = <List<Object>>[];
    await tester.pumpWidget(app(Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        CashMovementDialog(save: (kind, amount, reason) {
                          calls.add([kind, amount, reason]);
                          return done.future;
                        })),
                child: const Text('เปิด'))))));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, '44.001');
    await tester.enterText(find.byType(TextFormField).last, 'ซื้อน้ำแข็ง');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, '44');
    await tester.tap(find.text('บันทึก'));
    await tester.pump();
    await tester.tap(find.text('กำลังยืนยัน…'));
    expect(calls, [
      ['cashOut', 44.0, 'ซื้อน้ำแข็ง']
    ]);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CashMovementDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending cash entry retries original immutable values',
      (tester) async {
    final calls = <List<Object>>[];
    await tester.pumpWidget(app(Scaffold(
        body: CashMovementDialog(
            pending: const {
          'kind': 'cashOut',
          'amount': 44,
          'reason': 'ซื้อน้ำแข็ง'
        },
            save: (kind, amount, reason) async {
              calls.add([kind, amount, reason]);
              throw StateError('ลองอีกครั้ง');
            }))));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('ยืนยันรายการเดิม'));
      await tester.pumpAndSettle();
    }
    expect(calls, List.filled(2, ['cashOut', 44.0, 'ซื้อน้ำแข็ง']));
    expect(tester.widget<TextField>(find.byType(TextField).first).readOnly,
        isTrue);
  });

  test('cash close summary preserves new entries and reads legacy summaries',
      () {
    final summary = SessionSummary.fromMap(
        {'expectedCash': 576.25, 'cashIn': 20.25, 'cashOut': 44});
    expect(SessionSummary.fromMap(summary.toMap()).cashOut, 44);
    expect(summary.cashIn, 20.25);
    expect(SessionSummary.fromMap({}).cashIn, 0);
    expect(SessionSummary.fromMap({}).cashOut, 0);
  });
}
