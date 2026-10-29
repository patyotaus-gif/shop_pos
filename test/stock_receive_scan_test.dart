import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/screens/product_inventory_screen.dart';
import 'package:shop_pos/screens/stock_receive_scan_screen.dart';
import 'package:shop_pos/services/shop_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShopDatabase.overrideShop =
        FakeFirebaseFirestore().collection('shops').doc('scan-shop');
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  Future<void> seed(String id, {String mode = 'count'}) =>
      ShopDatabase.shop.collection('products').doc(id).set(Product(
              id: id,
              name: 'สินค้า $id',
              barcode: 'QR-001',
              price: 20,
              costPrice: 10,
              stock: 5,
              stockMode: mode)
          .toFirestore());

  Future<void> openOwner(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => openStockReceiveScanner(context),
                    child: const Text('เริ่ม'))))));
    await tester.tap(find.text('เริ่ม'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'owner scan reviews first, commits once and can scan next product',
      (tester) async {
    await seed('a');
    await openOwner(tester);
    await enterCode(tester, ' QR-001 ');
    expect(find.byType(AlertDialog), findsOneWidget);
    final ref = ShopDatabase.shop.collection('products').doc('a');
    expect((await ref.get()).data()!['stock'], 5);
    await tester.enterText(find.widgetWithText(TextField, 'จำนวนชิ้น'), '3');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect((await ref.get()).data()!['stock'], 8);
    expect((await ref.collection('stockMovements').get()).docs.length, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
    await enterCode(tester, 'QR-001');
    await tester.tap(find.text('ปิด'));
    await tester.pumpAndSettle();
    expect((await ref.get()).data()!['stock'], 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown, duplicate and recipe codes never open a receiving form',
      (tester) async {
    await openOwner(tester);
    await enterCode(tester, 'QR-001');
    expect(find.textContaining('ไม่พบสินค้า'), findsOneWidget);
    await seed('a');
    await seed('b');
    await enterCode(tester, 'QR-001');
    expect(find.textContaining('รหัสนี้ซ้ำ'), findsOneWidget);
    await ShopDatabase.shop.collection('products').doc('b').delete();
    await seed('a', mode: 'recipe');
    await enterCode(tester, 'QR-001');
    expect(find.textContaining('สินค้านี้ใช้สูตร'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        (await ShopDatabase.shop
                .collection('products')
                .doc('a')
                .collection('stockMovements')
                .get())
            .docs,
        isEmpty);
  });

  testWidgets('repeated submit stays locked while lookup or form is pending',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester
        .pumpWidget(MaterialApp(home: StockReceiveScanScreen(onCode: (_, code) {
      calls++;
      return pending.future;
    })));
    await tester.enterText(find.byType(TextField), '001');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });

  testWidgets(
      'camera cancellation does not lookup; QR value uses same confirmation path',
      (tester) async {
    String? scanResult;
    final codes = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: StockReceiveScanScreen(
            scan: (_) async => scanResult,
            onCode: (_, code) async {
              codes.add(code);
            })));
    await tester.tap(find.text('เปิดกล้องสแกน'));
    await tester.pumpAndSettle();
    expect(codes, isEmpty);
    scanResult = ' QR-001 ';
    await tester.tap(find.text('เปิดกล้องสแกน'));
    await tester.pumpAndSettle();
    expect(codes, ['QR-001']);
  });
}
