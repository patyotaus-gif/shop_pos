import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/screens/product_inventory_screen.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/services/inventory_service.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/services/sale_service.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/utils/stock_quantity.dart';
import 'package:shop_pos/widgets/stock_quantity_dialog.dart';

void main() {
  setUp(() {
    ShopDatabase.overrideShop =
        FakeFirebaseFirestore().collection('shops').doc('inventory');
  });
  tearDown(() => ShopDatabase.overrideShop = null);
  Product product({String id = 'rice', bool lots = false}) => Product(
      id: id,
      name: 'ข้าว',
      barcode: '',
      price: 80,
      costPrice: 40,
      stock: 2.5,
      isWeighed: true,
      unit: 'กก.',
      sku: id.toUpperCase(),
      trackLots: lots,
      stockLots: lots
          ? [
              {
                'id': 'late',
                'number': 'L2',
                'expiresOn': '2099-12-31',
                'quantity': 1.5
              },
              {
                'id': 'early',
                'number': 'L1',
                'expiresOn': '2099-01-01',
                'quantity': 1
              },
            ]
          : []);
  test('details preserve stock/cost/revision while SKU uniqueness is enforced',
      () async {
    final p = product();
    await ProductService.add(p);
    final ref = ShopDatabase.shop.collection('products').doc(p.id);
    await ref.update({'stock': 1.75, 'costPrice': 45, 'stockRevision': 2});
    await ProductService.update(p.copyWith(name: 'ข้าวใหม่'), original: p);
    final saved = (await ref.get()).data()!;
    expect(saved['stock'], 1.75);
    expect(saved['costPrice'], 45);
    expect(saved['stockRevision'], 2);
    await expectLater(
        ProductService.add(product(id: 'other').copyWith(sku: 'rice')),
        throwsStateError);
    await expectLater(
        ProductService.update(p.copyWith(unit: 'กรัม'), original: p),
        throwsStateError);
  });
  test(
      'receiving packs is idempotent and averages total cost; stale counts rejected',
      () async {
    final p = product().copyWith(unitsPerPack: 5);
    await ProductService.add(p);
    Future<void> receive() => InventoryService.change(
        productId: p.id,
        requestId: 'receipt-1',
        kind: 'receive',
        quantity: 2,
        reason: 'รับเข้า',
        packSize: 5,
        totalCost: 500);
    await receive();
    await receive();
    final ref = ShopDatabase.shop.collection('products').doc(p.id),
        saved = (await ref.get()).data()!;
    expect(saved['stock'], 12.5);
    expect(saved['costPrice'], 48);
    expect(saved['stockRevision'], 1);
    expect((await ref.collection('stockMovements').get()).size, 2);
    await expectLater(
        InventoryService.change(
            productId: p.id,
            requestId: 'receipt-1',
            kind: 'receive',
            quantity: 3,
            reason: 'รับเข้า'),
        throwsStateError);
    await expectLater(
        InventoryService.change(
            productId: p.id,
            requestId: 'count',
            kind: 'count',
            quantity: 2,
            reason: 'ตรวจนับ',
            expectedStock: 12.5,
            expectedRevision: 0),
        throwsStateError);
  });
  test('FEFO weighted checkout writes lot usage and history exactly once',
      () async {
    final p = product(lots: true);
    await ProductService.add(p);
    final sale = Sale(
        id: 'weighted',
        items: [
          SaleItem(
              productId: p.id,
              productName: p.name,
              price: 80,
              quantity: 1.25,
              subtotal: 100,
              unit: 'กก.',
              isWeighed: true)
        ],
        total: 100,
        discount: 0,
        paid: 100,
        change: 0,
        createdAt: DateTime.now());
    await SaleService.commitSale(ShopDatabase.shop, sale);
    await SaleService.commitSale(ShopDatabase.shop, sale);
    final ref = ShopDatabase.shop.collection('products').doc(p.id),
        saved = (await ref.get()).data()!;
    expect(saved['stock'], 1.25);
    final lots = saved['stockLots'] as List;
    expect(lots.first['id'], 'early');
    expect(lots.first['quantity'], 0);
    expect(lots.last['quantity'], 1.25);
    final receipt =
        (await ShopDatabase.shop.collection('sales').doc('weighted').get())
            .data()!;
    expect((receipt['stockLotsDeducted'] as Map)['rice'].length, 2);
    expect((await ref.collection('stockMovements').get()).size, 2);
    expect(Sale.fromFirestore(receipt, 'weighted').items.single.quantity, 1.25);
  });
  test('expired lots excluded, reservations prevent inventory reduction',
      () async {
    final p = product(lots: true);
    await ProductService.add(p);
    final map = p.toFirestore();
    expect(saleableStock(map, today: '2099-01-02'), 1.5);
    expect(() => allocateStock(map, 2, today: '2099-01-02'), throwsStateError);
    await ShopDatabase.shop.collection('inventoryControl').doc('online').set({
      'products': {'rice': 2}
    });
    await expectLater(
        InventoryService.change(
            productId: p.id,
            requestId: 'waste',
            kind: 'waste',
            quantity: 1,
            lotId: 'early',
            reason: 'เสีย'),
        throwsStateError);
    expect(
        (await ShopDatabase.shop.collection('products').doc(p.id).get())
            .data()!['stock'],
        2.5);
  });
  test(
      'count products reject fractions and weighted numbers reject excess precision',
      () async {
    expect(validStockQuantity(0.125, weight: true), isTrue);
    expect(validStockQuantity(0.125), isFalse);
    expect(validStockQuantity(0.0001, weight: true), isFalse);
    expect(validStockQuantity(double.nan, weight: true), isFalse);
    final p = product().copyWith(isWeighed: false, stock: 2);
    await ProductService.add(p);
    await expectLater(
        InventoryService.change(
            productId: p.id,
            requestId: 'bad',
            kind: 'receive',
            quantity: 0.5,
            reason: 'รับเข้า'),
        throwsStateError);
  });
  testWidgets('weight editor keeps 250 grams as 0.250 kg', (tester) async {
    num? quantity;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  quantity = await showStockQuantity(context,
                      unit: 'กก.', weighed: true);
                },
                child: const Text('เลือก')))));
    await tester.tap(find.text('เลือก'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0.250');
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(quantity, 0.25);
  });
  test('a package may contain a fractional selling unit', () async {
    final p = product().copyWith(unitsPerPack: 0.25);
    await ProductService.add(p);
    await InventoryService.change(
        productId: p.id,
        requestId: 'packs',
        kind: 'receive',
        quantity: 2,
        packSize: 0.25,
        reason: 'รับสองถุง');
    expect(
        (await ShopDatabase.shop.collection('products').doc(p.id).get())
            .data()!['stock'],
        3);
  });
  test('decimal reservations do not reject exact remaining weighted stock',
      () async {
    final p = product().copyWith(stock: 0.3);
    await ProductService.add(p);
    await ShopDatabase.shop.collection('inventoryControl').doc('online').set({
      'products': {p.id: 0.1}
    });
    await SaleService.commitSale(
        ShopDatabase.shop,
        Sale(
            id: 'exact-stock',
            items: [
              SaleItem(
                  productId: p.id,
                  productName: p.name,
                  price: 80,
                  quantity: 0.2,
                  subtotal: 16)
            ],
            total: 16,
            discount: 0,
            paid: 16,
            change: 0,
            createdAt: DateTime.now()));
    expect(
        (await ShopDatabase.shop.collection('products').doc(p.id).get())
            .data()!['stock'],
        0.1);
  });
  testWidgets('phone inventory receiving flow saves quantity and history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = product();
    await ProductService.add(p);
    await tester
        .pumpWidget(MaterialApp(home: ProductInventoryScreen(productId: p.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รับสินค้าเข้า'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'จำนวนกก.'), '0.125');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(
        (await ShopDatabase.shop.collection('products').doc(p.id).get())
            .data()!['stock'],
        2.625);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
