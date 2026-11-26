import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/pos_catalog.dart';
import 'package:shop_pos/widgets/pos_basket.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'helpers/signed_out_firebase.dart';

const product =
    Product(id: 'rice', name: 'ข้าวผัด', barcode: '1', price: 35, stock: 20);
TableOrder orderWith(List<TableOrderItem> items, {bool quote = false}) =>
    TableOrder(
      id: 'order',
      tableId: 't2',
      tableName: '2',
      openedAt: DateTime(2026),
      items: items,
      promotion: quote
          ? {
              'lines': items
                  .map((i) => {
                        'id': i.id,
                        'productId': i.productId,
                        'quantity': i.quantity,
                        'unitPrice': i.unitPrice
                      })
                  .toList(),
              'subtotalMinor': items.fold<num>(
                  0, (sum, i) => sum + (i.subtotal * 100).round()),
              'discountMinor': 0,
              'serviceChargePercent': 0,
              'serviceMinor': 0,
              'totalMinor': items.fold<num>(
                  0, (sum, i) => sum + (i.subtotal * 100).round()),
              'revision': items.map((i) => '${i.id}:${i.quantity}').join(','),
            }
          : null,
    );

void main() {
  setupSignedOutFirebase();
  setUp(() {
    ShopDatabase.overrideShop =
        FakeFirebaseFirestore().collection('shops').doc('fixture');
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  Future<void> openTable(WidgetTester tester,
      {bool rejectQuote = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1480, 924);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final order = orderWith([
      const TableOrderItem(
          id: 'old',
          productId: 'coffee',
          productName: 'กาแฟ',
          price: 45,
          quantity: 1,
          kitchenStatus: KitchenStatus.sent)
    ], quote: true);
    await ShopDatabase.shop
        .collection('products')
        .doc(product.id)
        .set(product.toFirestore());
    final ref = ShopDatabase.shop.collection('tableOrders').doc(order.id);
    await ref.set(order.toFirestore());
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
          body: StreamBuilder(
              stream: ref.snapshots(),
              builder: (_, snap) => !snap.hasData
                  ? const SizedBox()
                  : TableOrderView(
                      order: TableOrder.fromFirestore(
                          snap.data!.data()!, order.id),
                      loyaltyEnabled: false,
                      loadServiceCharge: () async => 0,
                      syncPromotions: (current,
                          {bool send = false,
                          bool keepPreparedGifts = false,
                          String reason = ''}) async {
                        if (rejectQuote) throw StateError('ตรวจยอดไม่ได้');
                        final confirmed = orderWith(
                            current.items
                                .map((i) => send
                                    ? i.copyWith(
                                        kitchenStatus: KitchenStatus.sent)
                                    : i)
                                .toList(),
                            quote: true);
                        await ref.update(confirmed.toFirestore());
                        return confirmed;
                      },
                    )),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
  }

  testWidgets('table uses takeaway workspace and pays without leaving catalog',
      (tester) async {
    await openTable(tester);
    expect(find.text('ขายที่โต๊ะ 2'), findsOneWidget);
    expect(tester.getRect(find.byType(PosCatalog)).right,
        lessThanOrEqualTo(tester.getRect(find.byType(PosBasket)).left));
    expect(find.text('ค้นหาเมนูอาหาร'), findsOneWidget);
    expect(
        find.textContaining('สถานะเมื่อโหลดบิล · ส่งครัวแล้ว'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    expect(find.text('รายการใหม่ · ยังไม่บันทึก'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('฿115.00'), findsWidgets);
    expect(find.textContaining('ข้าวผัด × 2'), findsOneWidget);
    expect(find.byType(TableProductPicker), findsOneWidget);
    final ref = ShopDatabase.shop.collection('tableOrders').doc('order');
    var saved = (await ref.get()).data()!;
    expect(saved['appliedItemBatchIds'], hasLength(1));
    expect(TableOrder.fromFirestore(saved, 'order').itemCount, 3);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect((await ref.get()).data()!['appliedItemBatchIds'], hasLength(1));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    saved = (await ref.get()).data()!;
    expect(saved['appliedItemBatchIds'], hasLength(2));
    expect(TableOrder.fromFirestore(saved, 'order').itemCount, 4);
    expect(find.text('฿150.00'), findsWidgets);
    expect((await ShopDatabase.shop.collection('sales').get()).docs, isEmpty);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failed quote stays on sales page with saved items and visible error',
      (tester) async {
    await openTable(tester, rejectQuote: true);
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TableProductPicker), findsOneWidget);
    expect(find.textContaining('ตรวจยอดไม่ได้'), findsOneWidget);
    expect((await TableService.readOrder('order')).itemCount, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'lost save reply freezes displayed baseline and retries only one batch',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1480, 924);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final current = ValueNotifier(orderWith([
      const TableOrderItem(
          id: 'old',
          productId: 'coffee',
          productName: 'กาแฟ',
          price: 45,
          quantity: 1)
    ]));
    addTearDown(current.dispose);
    final requests = <String>[];
    var payments = 0;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: TableProductPicker(
          tableName: '2',
          order: current,
          products: Stream.value([product]),
          save: (items, request) async {
            requests.add(request);
            if (requests.length == 1) {
              current.value = orderWith([...current.value.items, ...items]);
              throw StateError('ไม่ได้รับคำตอบ');
            }
          },
          checkout: (_) async {
            payments++;
          },
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-product-rice')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.text('รายการขาย · 2 รายการ'), findsOneWidget);
    expect(find.text('฿80.00'), findsOneWidget);
    expect(payments, 0);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.first, requests.last);
    expect(current.value.itemCount, 2);
    expect(payments, 1);
    expect(find.text('รายการขาย · 2 รายการ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
