import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cash_close_check.dart';
import 'package:shop_pos/screens/cash_close_issue_screen.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'helpers/signed_out_firebase.dart';
import 'table_sales_flow_test.dart' show orderWith, product;

void main() {
  setupSignedOutFirebase();
  setUp(() => ShopDatabase.overrideShop =
      FakeFirebaseFirestore().collection('shops').doc('cash-close-fixture'));
  tearDown(() => ShopDatabase.overrideShop = null);

  testWidgets('cash-close requires an explicit open record status',
      (tester) async {
    final records = StreamController<Map<String, dynamic>?>();
    addTearDown(records.close);
    final order = orderWith([]).toFirestore();
    await tester.pumpWidget(MaterialApp(
        home: CashCloseIssueScreen(
      issue: const CashCloseIssue(
          type: 'openTable',
          id: 'order',
          label: 'โต๊ะ 2',
          message: 'บิลยังเปิด'),
      tableRecords: records.stream,
    )));
    final invalid = <Map<String, dynamic>?>[
      {...order}..remove('status'),
      {...order, 'status': 'unexpected'},
      {...order, 'status': 'closed'},
      null,
    ];
    for (final value in invalid) {
      records.add(order);
      await tester.pumpAndSettle();
      expect(find.byType(TableOrderView), findsOneWidget);
      records.add(value);
      await tester.pumpAndSettle();
      expect(find.byType(TableOrderView), findsNothing);
      expect(
          find.text('บิลนี้ไม่ค้างแล้ว กลับไปตรวจปิดยอดได้'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'cash-close table draft survives stream error and can save on recovery',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1480, 924);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final records = StreamController<Map<String, dynamic>?>();
    addTearDown(records.close);
    final order = orderWith([]);
    await ShopDatabase.shop
        .collection('tableOrders')
        .doc(order.id)
        .set(order.toFirestore());
    await ShopDatabase.shop
        .collection('products')
        .doc(product.id)
        .set(product.toFirestore());
    await tester.pumpWidget(MaterialApp(
        home: CashCloseIssueScreen(
      issue: const CashCloseIssue(
          type: 'openTable',
          id: 'order',
          label: 'โต๊ะ 2',
          message: 'บิลยังเปิด'),
      tableRecords: records.stream,
    )));
    records.add(order.toFirestore());
    await tester.pumpAndSettle();
    final session = tester.state(find.byType(TableOrderView));
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    records.addError(StateError('offline-fixture'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TableOrderView, skipOffstage: false)),
        same(session));
    await tester.tap(find.text('เพิ่มลงโต๊ะ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await TableService.readOrder('order')).items, isEmpty);
    records.add(order.toFirestore());
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TableOrderView, skipOffstage: false)),
        same(session));
    await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await TableService.readOrder('order')).itemCount, 1);
    // Avoid the native quote plugin: this fixture exercises saving, not payment.
    await tester.pumpWidget(const SizedBox());
  });
}
