import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/payment_sheet.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'package:shop_pos/widgets/stock_quantity_dialog.dart';
import 'helpers/signed_out_firebase.dart';
import 'table_sales_flow_test.dart' show orderWith, product;

void main() {
  setupSignedOutFirebase();
  setUp(() {
    ShopDatabase.overrideShop =
        FakeFirebaseFirestore().collection('shops').doc('recovery');
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  void screen(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1480, 924);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  Future<ValueNotifier<TableOrder>> open(
    WidgetTester tester, {
    Future<void> Function()? beforeQuote,
    Future<TableOrder> Function(String)? readOrder,
    Future<String> Function(TableOrder, PaymentResult, int)? closeOrder,
  }) async {
    screen(tester);
    final initial = orderWith([
      const TableOrderItem(
          id: 'coffee',
          productId: 'coffee',
          productName: 'กาแฟ',
          price: 45,
          quantity: 1,
          kitchenStatus: KitchenStatus.sent)
    ], quote: true);
    final displayed = ValueNotifier(initial);
    addTearDown(displayed.dispose);
    await ShopDatabase.shop
        .collection('tableOrders')
        .doc(initial.id)
        .set(initial.toFirestore());
    await ShopDatabase.shop
        .collection('products')
        .doc(product.id)
        .set(product.toFirestore());
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: Builder(
          builder: (context) => TextButton(
              child: const Text('เลือกโต๊ะ'),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      body: ValueListenableBuilder<TableOrder>(
                          valueListenable: displayed,
                          builder: (_, order, __) => TableOrderView(
                                order: order,
                                loyaltyEnabled: false,
                                loadServiceCharge: () async => 0,
                                readOrder: readOrder,
                                closeOrder: closeOrder,
                                receiptBuilder: (id) => Scaffold(
                                    body: Builder(
                                        builder: (context) => TextButton(
                                            child: Text('ขายต่อ $id'),
                                            onPressed: () =>
                                                Navigator.pop(context)))),
                                syncPromotions: (current,
                                    {bool send = false,
                                    bool keepPreparedGifts = false,
                                    String reason = ''}) async {
                                  await beforeQuote?.call();
                                  return orderWith(
                                      current.items
                                          .map((i) => send
                                              ? i.copyWith(
                                                  kitchenStatus:
                                                      KitchenStatus.sent)
                                              : i)
                                          .toList(),
                                      quote: true);
                                },
                              )),
                    ),
                  ))),
        ))));
    await tester.tap(find.text('เลือกโต๊ะ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
    return displayed;
  }

  Future<void> addRice(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
  }

  testWidgets('a rebound table cannot write the draft to a replacement bill',
      (tester) async {
    final displayed = await open(tester);
    await addRice(tester);
    final replacement = TableOrder(
        id: 'replacement',
        tableId: 't2',
        tableName: '2',
        items: [],
        openedAt: DateTime(2026));
    await ShopDatabase.shop
        .collection('tableOrders')
        .doc(replacement.id)
        .set(replacement.toFirestore());
    displayed.value = replacement;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.textContaining('บิลของโต๊ะเปลี่ยนแล้ว'), findsOneWidget);
    expect((await TableService.readOrder('replacement')).items, isEmpty);
    expect((await TableService.readOrder('order')).itemCount, 1);
    expect(find.byType(Dialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a delayed old poll cannot erase the readback during a payment quote',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    final displayed = await open(tester, beforeQuote: () async {
      if (++calls == 1) await gate.future;
    });
    final old = displayed.value;
    await addRice(tester);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    displayed.value = orderWith(old.items, quote: true);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('฿80.00'), findsWidgets);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'a timed out read returning after retry cannot replace the newer total',
      (tester) async {
    final lateRead = Completer<TableOrder>();
    var reads = 0;
    final displayed = await open(tester, readOrder: (id) async {
      if (++reads == 1) return lateRead.future;
      return TableService.readOrder(id);
    });
    final old = displayed.value;
    await addRice(tester);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('฿80.00'), findsWidgets);
    lateRead.complete(old);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(find.text('฿80.00'), findsOneWidget);
    final saved =
        (await ShopDatabase.shop.collection('tableOrders').doc('order').get())
            .data()!;
    expect(saved['appliedItemBatchIds'], hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'order stream errors preserve the draft but block saving until recovery',
      (tester) async {
    screen(tester);
    final orders = StreamController<TableOrder?>();
    addTearDown(orders.close);
    final initial = orderWith([]);
    await ShopDatabase.shop
        .collection('tableOrders')
        .doc('order')
        .set(initial.toFirestore());
    await ShopDatabase.shop
        .collection('products')
        .doc(product.id)
        .set(product.toFirestore());
    await tester.pumpWidget(MaterialApp(
        home: TableDetailScreen(
            table:
                RestaurantTable(id: 't2', name: '2', createdAt: DateTime(2026)),
            orders: orders.stream)));
    orders.add(initial);
    await tester.pumpAndSettle();
    final before = tester.state(find.byType(TableOrderView));
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
    await addRice(tester);
    orders.addError(StateError('พบหลายบิลในโต๊ะเดียวกัน'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TableOrderView, skipOffstage: false)),
        same(before));
    await tester.tap(find.text('เพิ่มลงโต๊ะ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await TableService.readOrder('order')).items, isEmpty);
    expect(find.textContaining('พบหลายบิลในโต๊ะเดียวกัน'), findsOneWidget);
    orders.add(initial);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TableOrderView, skipOffstage: false)),
        same(before));
    expect(find.byType(TableProductPicker), findsOneWidget);
    await tester.tap(find.text('ลองบันทึกอีกครั้ง'));
    // This fixture covers batch recovery, not the detail screen's delayed quote.
    // Dispose before its 400 ms automatic quote would call the native plugin.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect((await TableService.readOrder('order')).itemCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a late return read cannot erase a newer table snapshot',
      (tester) async {
    final lateRead = Completer<TableOrder>();
    final displayed = await open(tester, readOrder: (_) => lateRead.future);
    final latest = orderWith([
      ...displayed.value.items,
      TableService.itemFromProduct(product),
    ], quote: true);
    await tester.tap(find.byKey(const ValueKey('table-catalog-back')));
    await tester.pumpAndSettle();
    displayed.value = latest;
    await tester.pumpAndSettle();
    lateRead.complete(orderWith([]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
    expect(find.text('฿80.00'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('checkout-pay')))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'quantity edit survives another table line and rotation while its dialog is open',
      (tester) async {
    screen(tester);
    final current = ValueNotifier(orderWith([]));
    addTearDown(current.dispose);
    List<TableOrderItem>? saved;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: TableProductPicker(
          tableName: '2',
          order: current,
          products: Stream.value([product]),
          save: (items, _) async {
            saved = items;
            current.value = orderWith([...current.value.items, ...items]);
          },
          checkout: (_) async {},
        )));
    await tester.pumpAndSettle();
    await addRice(tester);
    await tester.tap(find.widgetWithText(TextButton, '1'));
    await tester.pumpAndSettle();
    current.value = orderWith([
      const TableOrderItem(
          id: 'coffee',
          productId: 'coffee',
          productName: 'กาแฟ',
          price: 45,
          quantity: 1)
    ]);
    tester.view.physicalSize = const Size(800, 1100);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(StockQuantityDialog),
            matching: find.byType(TextField)),
        '3');
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.text('ตะกร้า 4 หน่วย · ฿150.00'), findsOneWidget);
    await tester.tap(find.text('ตะกร้า 4 หน่วย · ฿150.00'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(saved!.single.quantity, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'confirmed table payment returns from receipt straight to table selection',
      (tester) async {
    var paid = 0;
    await open(tester, closeOrder: (order, result, split) async {
      paid++;
      expect(order.id, 'order');
      expect(order.subtotal, 80);
      expect(result.paid, 100);
      return 'fixture-sale';
    });
    await addRice(tester);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'จำนวนเงินที่รับ'), '100');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันการชำระเงิน'));
    await tester.pumpAndSettle();
    expect(paid, 1);
    expect(find.text('ขายต่อ fixture-sale'), findsOneWidget);
    await tester.tap(find.text('ขายต่อ fixture-sale'));
    await tester.pumpAndSettle();
    expect(find.text('เลือกโต๊ะ'), findsOneWidget);
    expect(find.byType(TableOrderView), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
