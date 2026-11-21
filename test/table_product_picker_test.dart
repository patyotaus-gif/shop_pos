import 'dart:async';
import 'helpers/signed_out_firebase.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/modifier_group.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'package:shop_pos/widgets/modifier_picker_sheet.dart';
import 'package:shop_pos/widgets/stock_quantity_dialog.dart';
import 'package:shop_pos/widgets/pos_catalog.dart';
import 'package:shop_pos/widgets/pos_basket.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';

const brownie = Product(
    id: 'brownie',
    name: 'Brownie',
    barcode: '1',
    price: 35,
    stock: 100,
    category: 'ขนม');
const cookie = Product(
    id: 'cookie',
    name: 'Cookie',
    barcode: '2',
    price: 25,
    stock: 100,
    category: 'ขนม');
const weighed = Product(
    id: 'weight',
    name: 'สินค้าชั่ง',
    barcode: '3',
    price: 100,
    stock: 100,
    isWeighed: true,
    unit: 'กก.');

Future<void> openPicker(WidgetTester tester,
    Future<void> Function(List<TableOrderItem>, String) save,
    {List<Product> products = const [brownie, cookie, weighed],
    Stream<List<Product>>? stream,
    Size size = const Size(1480, 924),
    double textScale = 1,
    Future<ModifierPick?> Function(BuildContext, Product)?
        chooseModifiers}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: PokpokTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                  onPressed: () =>
                      Navigator.of(context).push<void>(MaterialPageRoute<void>(
                    builder: (_) => TableProductPicker(
                        tableName: '2',
                        save: save,
                        products: stream ?? Stream.value(products),
                        chooseModifiers: chooseModifiers),
                  )),
                  child: const Text('open'),
                ))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setupSignedOutFirebase();

  testWidgets(
      'production picker entry opens a full page for the selected table',
      (tester) async {
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.collection('shops').doc('fixture');
    addTearDown(() => ShopDatabase.overrideShop = null);
    await ShopDatabase.shop
        .collection('products')
        .doc('brownie')
        .set(brownie.toFirestore());
    tester.view.physicalSize = const Size(1480, 924);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showTableProductPicker(context,
                        orderId: 'fixture-order', tableName: '2'),
                    child: const Text('เพิ่มสินค้า'))))));
    await tester.tap(find.text('เพิ่มสินค้า'));
    await tester.pumpAndSettle();
    expect(find.text('ขายที่โต๊ะ 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('sale-product-brownie')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
        tester.getSize(find.byType(TableProductPicker)), const Size(1480, 924));
    await tester.tap(find.byKey(const ValueKey('table-catalog-back')));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มสินค้า'), findsOneWidget);
  });

  testWidgets('table catalog fills the tablet page instead of a modal',
      (tester) async {
    await openPicker(tester, (_, __) async {}, size: const Size(1480, 924));
    expect(find.byType(BottomSheet), findsNothing);
    final bounds = tester.getRect(find.byType(TableProductPicker));
    expect(bounds.left, 0);
    expect(bounds.width, 1480);
    expect(bounds.height, 924);
    expect(find.byKey(const ValueKey('table-catalog-back')), findsOneWidget);
    expect(find.text('ขายที่โต๊ะ 2'), findsOneWidget);
    final catalog = tester.getRect(find.byType(PosCatalog));
    final basket = tester.getRect(find.byType(PosBasket));
    expect(catalog.right, lessThanOrEqualTo(basket.left));
    expect(basket.width, 380);
  });

  testWidgets(
      'required modifiers cannot be skipped and cancelling adds nothing',
      (tester) async {
    List<TableOrderItem>? saved;
    final product = brownie.copyWith(modifierGroupIds: ['size']);
    await openPicker(
      tester,
      (items, _) async => saved = items,
      products: [product],
      chooseModifiers: (context, product) =>
          showModifierPicker(context, product: product, offlineGroups: [
        ModifierGroup(
            id: 'size',
            name: 'ขนาด',
            required: true,
            createdAt: DateTime(2026),
            options: const [
              ModifierOption(id: 'large', name: 'ใหญ่', priceAdjust: 10),
            ])
      ]),
    );
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    final add = find.widgetWithText(FilledButton, 'เพิ่มเข้าตะกร้า');
    expect(tester.widget<FilledButton>(add).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('รายการขาย · 0 รายการ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใหญ่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มเข้าตะกร้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงโต๊ะ · ฿45.00'));
    await tester.pumpAndSettle();
    expect(saved!.single.modifiers.single.optionId, 'large');
    expect(saved!.single.subtotal, 45);
  });

  testWidgets('keyboard leaves catalog scrollable on a small phone',
      (tester) async {
    await openPicker(tester, (_, __) async {}, size: const Size(320, 640));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), 'Brownie');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final productName = find.descendant(
        of: find.byKey(const ValueKey('sale-search-brownie')),
        matching: find.text('Brownie'));
    await tester.ensureVisible(productName);
    await tester.pumpAndSettle();
    await tester.tap(productName);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ตะกร้า 1 หน่วย · ฿35.00'), findsOneWidget);
  });

  testWidgets('catalog errors are shown instead of an empty catalog',
      (tester) async {
    await openPicker(tester, (_, __) async {},
        stream: Stream.error(StateError('โหลดสินค้าไม่ได้')));
    expect(
        find.text('โหลดสินค้าไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'), findsOneWidget);
    expect(find.text('ไม่พบสินค้า'), findsNothing);
  });

  testWidgets('tap products repeatedly, preserve category, and save one batch',
      (tester) async {
    final saves = <List<TableOrderItem>>[];
    await openPicker(tester, (items, key) async => saves.add(items));
    await tester.tap(find.text('ขนม'));
    await tester.enterText(find.byType(TextField), 'brown');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-search-brownie')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    expect(saves, isEmpty);
    expect(find.widgetWithText(TextButton, '2'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('sales-tab-category:ขนม')))
            .selected,
        isTrue);
    expect(find.text('รายการขาย · 1 รายการ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-product-cookie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงโต๊ะ · ฿95.00'));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.single.map((item) => item.quantity), [2, 1]);
    expect(saves.single.every((i) => i.kitchenStatus == KitchenStatus.pending),
        isTrue);
    expect(find.byType(TableProductPicker), findsNothing);
  });

  testWidgets(
      'weight selection and explicit notes remain available; review removes draft',
      (tester) async {
    List<TableOrderItem>? saved;
    await openPicker(tester, (items, key) async => saved = items,
        products: const [weighed, brownie]);
    await tester.tap(find.byKey(const ValueKey('sale-product-weight')));
    await tester.pumpAndSettle();
    expect(find.byType(StockQuantityDialog), findsOneWidget);
    await tester.enterText(
        find.descendant(
            of: find.byType(StockQuantityDialog),
            matching: find.byType(TextField)),
        '0.250');
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('sales-search')), 'Brownie');
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตัวเลือก / หมายเหตุ'));
    await tester.pumpAndSettle();
    final noteField = find.byType(TextField).last;
    await tester.enterText(noteField, 'ไม่อุ่น');
    await tester.tap(find.text('เพิ่มเข้าตะกร้า'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ไม่อุ่น'), findsOneWidget);
    await tester.tap(find.byTooltip('ลบรายการ').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงโต๊ะ · ฿35.00'));
    await tester.pumpAndSettle();
    expect(saved!.single.notes, 'ไม่อุ่น');
  });

  testWidgets(
      'failed response freezes draft and retry uses same batch and request id',
      (tester) async {
    final keys = <String>[];
    final batches = <List<TableOrderItem>>[];
    final completed = Completer<void>();
    await openPicker(tester, (items, key) async {
      keys.add(key);
      batches.add(items);
      if (keys.length == 1) throw StateError('เครือข่ายขัดข้อง');
      await completed.future;
    });
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มลงโต๊ะ · ฿35.00'));
    await tester.pumpAndSettle();
    expect(
        find.ancestor(
            of: find.byType(CartItemTile),
            matching: find
                .byWidgetPredicate((w) => w is AbsorbPointer && w.absorbing)),
        findsOneWidget);
    await tester.tap(find.text('ลองบันทึกอีกครั้ง · ฿35.00'));
    await tester.pump();
    expect(
        tester
            .widget<IconButton>(
                find.byKey(const ValueKey('table-catalog-back')))
            .onPressed,
        isNull);
    await tester.tap(find.text('กำลังเพิ่มลงโต๊ะ…'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(keys, hasLength(2));
    expect(keys.first, keys.last);
    expect(identical(batches.first, batches.last), isTrue);
    expect(find.byType(TableProductPicker), findsOneWidget);
    completed.complete();
    await tester.pumpAndSettle();
    expect(find.byType(TableProductPicker), findsNothing);
  });

  testWidgets('back confirms discarding selections', (tester) async {
    var saves = 0;
    await openPicker(tester, (_, __) async {
      saves++;
    });
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('ออกจากการเลือกสินค้า?'), findsOneWidget);
    await tester.tap(find.text('ออกจากหน้านี้'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.byType(TableProductPicker), findsNothing);
  });

  testWidgets('page back keeps draft when discard is declined', (tester) async {
    var saves = 0;
    await openPicker(tester, (_, __) async {
      saves++;
    });
    await tester.tap(find.byKey(const ValueKey('sale-product-brownie')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('table-catalog-back')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกสินค้าต่อ'));
    await tester.pumpAndSettle();
    expect(find.text('รายการขาย · 1 รายการ'), findsOneWidget);
    expect(saves, 0);
    expect(find.byType(TableProductPicker), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(800, 1100),
    const Size(844, 390)
  ]) {
    testWidgets('catalog fits $size with large text', (tester) async {
      await openPicker(tester, (_, __) async {}, size: size, textScale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Brownie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Brownie'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('ตะกร้า 1 หน่วย · ฿35.00'), findsOneWidget);
    });
  }

  group('table batch transaction', () {
    late FakeFirebaseFirestore db;
    setUp(() async {
      db = FakeFirebaseFirestore();
      ShopDatabase.overrideShop = db.collection('shops').doc('test');
      await ShopDatabase.shop.collection('tableOrders').doc('order').set(
              TableOrder(
                  id: 'order',
                  tableId: 'table',
                  tableName: '1',
                  openedAt: DateTime(2026),
                  items: [
                const TableOrderItem(
                    id: 'sent',
                    productId: 'brownie',
                    productName: 'Brownie',
                    price: 35,
                    quantity: 2,
                    kitchenStatus: KitchenStatus.sent),
              ]).toFirestore());
    });
    tearDown(() => ShopDatabase.overrideShop = null);

    test('one atomic batch, retry never duplicates; sent items stay separate',
        () async {
      final items = [
        TableService.itemFromProduct(brownie, quantity: 2),
        TableService.itemFromProduct(cookie)
      ];
      await TableService.addItems('order', items, requestId: 'batch');
      await TableService.addItem('order', TableService.itemFromProduct(cookie));
      await TableService.addItems('order', items, requestId: 'batch');
      final snap =
          await ShopDatabase.shop.collection('tableOrders').doc('order').get();
      final order = TableOrder.fromFirestore(snap.data()!, snap.id);
      expect(order.items, hasLength(3));
      expect(order.items[0].kitchenStatus, KitchenStatus.sent);
      expect(order.items[1].quantity, 2);
      expect(order.items[2].quantity, 2);
      expect(snap.data()!['appliedItemBatchIds'], ['batch']);
    });

    test('invalid and closed batches do not partially write', () async {
      await expectLater(
          TableService.addItems(
              'order',
              [
                TableService.itemFromProduct(cookie),
                TableService.itemFromProduct(brownie, quantity: -1),
              ],
              requestId: 'bad'),
          throwsStateError);
      final ref = ShopDatabase.shop.collection('tableOrders').doc('order');
      expect((await ref.get()).data()!['items'], hasLength(1));
      await ref.update({'status': 'closed'});
      await expectLater(
          TableService.addItems('order', [TableService.itemFromProduct(cookie)],
              requestId: 'closed'),
          throwsStateError);
      expect((await ref.get()).data()!['items'], hasLength(1));
    });
  });
}
