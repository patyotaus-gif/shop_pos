// Copy into test/ in a current checkout and set STORY_OUTPUT to a directory.
// All inputs are synthetic. No backend, sale or payment is created.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/receipt_profile.dart';
import 'package:shop_pos/utils/receipt_generator.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/pos_screen.dart';
import 'package:shop_pos/services/sale_display_service.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/payment_sheet.dart';
import 'package:shop_pos/widgets/sales_insights.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';
import 'package:shop_pos/widgets/pos_catalog.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';
import 'package:shop_pos/widgets/product_catalog.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'package:shop_pos/widgets/sale_display_controls.dart';
import 'package:shop_pos/widgets/side_navigation_shell.dart';
import 'helpers/signed_out_firebase.dart';

void main() {
  setupSignedOutFirebase();
  testWidgets('capture retail sales, stock, report and a matching table bill',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final weight in ['Regular', 'SemiBold', 'Bold']) {
      await (FontLoader(PokpokTheme.fontFamily)
            ..addFont(
                rootBundle.load('assets/fonts/IBMPlexSansThai-$weight.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final display = SaleDisplayController('website-demo');
    await display.load();
    await display.save(display.value.withMode(SaleDisplayMode.names));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    final navigator = GlobalKey<NavigatorState>();
    Future<void> mount(Widget home, Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              navigatorKey: navigator,
              debugShowCheckedModeBanner: false,
              theme: PokpokTheme.light(),
              home: SaleDisplayScope(controller: display, child: home))));
      await tester.pumpAndSettle();
    }

    Future<void> save(String name) async {
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      void repaint(RenderObject o) {
        o.markNeedsPaint();
        o.visitChildren(repaint);
      }

      repaint(render);
      await tester.pump();
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${Platform.environment["STORY_OUTPUT"]}/$name-1.2.84.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    const retail = [
      Product(
          id: 'water',
          name: 'น้ำดื่ม 600 มล.',
          barcode: '',
          price: 10,
          stock: 24,
          category: 'เครื่องดื่ม'),
      Product(
          id: 'milk',
          name: 'นมจืด',
          barcode: '',
          price: 15,
          stock: 12,
          category: 'เครื่องดื่ม'),
      Product(
          id: 'snack',
          name: 'มันฝรั่งทอด',
          barcode: '',
          price: 20,
          stock: 8,
          category: 'ขนม'),
      Product(
          id: 'paper',
          name: 'กระดาษทิชชู',
          barcode: '',
          price: 25,
          stock: 6,
          category: 'ของใช้'),
    ];
    await mount(
        Scaffold(
            body: SafeArea(
                child: PosCatalog(
                    loadProducts: () => Stream.value(retail), onAdd: (_) {}))),
        const Size(590, 400));
    expect(find.text(retail.first.name), findsWidgets);
    await save('retail-sale');

    // The website's full-screen preview uses the app's retail sales route.
    // Only the shop and product records are fixtures. The cart is filled by tapping.
    final shop = FakeFirebaseFirestore().collection('shops').doc('retail-demo');
    ShopDatabase.overrideShop = shop;
    addTearDown(() => ShopDatabase.overrideShop = null);
    await shop
        .set({'name': 'มินิมาร์ทสาธิต', 'shopType': 'retail', 'tier': 'lite'});
    for (final p in retail) {
      final photo = File('scripts/fixtures/retail-products/${p.id}.jpg');
      expect(photo.existsSync(), isTrue);
      await tester.runAsync(() => precacheImage(
          FileImage(photo.absolute), boundary.currentContext!,
          onError: (error, stack) => fail('Could not load ${p.id}: $error')));
      await shop
          .collection('products')
          .doc(p.id)
          .set(p.copyWith(imagePath: photo.absolute.path).toFirestore());
    }
    // Use the same navigation shell and retail labels as MainShell without
    // mounting the background tabs that subscribe to other shop services.
    const navigation = [
      ('ขาย', Icons.point_of_sale_outlined, Icons.point_of_sale),
      ('ออเดอร์', Icons.shopping_bag_outlined, Icons.shopping_bag),
      ('สินค้า', Icons.inventory_2_outlined, Icons.inventory_2),
      ('รายงาน', Icons.bar_chart_outlined, Icons.bar_chart),
      (
        'เครื่องมือส่งเสริมการขาย',
        Icons.local_offer_outlined,
        Icons.local_offer
      ),
      ('ผู้ช่วยร้าน', Icons.auto_awesome_outlined, Icons.auto_awesome),
      ('ลิงก์และ QR สั่งสินค้า', Icons.qr_code_2_outlined, Icons.qr_code_2),
      ('ตั้งค่า', Icons.settings_outlined, Icons.settings),
    ];
    for (final name in [
      'assets/icon/icon.png',
      'assets/brand/pokpok-wordmark.png'
    ]) {
      await tester.runAsync(
          () => precacheImage(AssetImage(name), boundary.currentContext!));
    }
    await mount(
        SideNavigationShell(selectedIndex: 0, onSelected: (_) {}, items: [
          for (final tab in navigation)
            AppNavigationItem(
                label: tab.$1,
                icon: tab.$2,
                selectedIcon: tab.$3,
                screen: tab == navigation.first
                    ? const PosScreen()
                    : const SizedBox.shrink()),
        ]),
        const Size(1152, 720));
    for (final p in retail.take(2)) {
      await tester.tap(find.text(p.name).hitTestable());
      await tester.pumpAndSettle();
    }
    expect(find.text('ขายหน้าร้าน'), findsOneWidget);
    expect(find.byType(CartItemTile), findsNWidgets(2));
    expect(
        find.descendant(
            of: find.byType(PosCheckoutPanel), matching: find.text('฿25.00')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('checkout-pay')).hitTestable(),
        findsOneWidget);
    await save('retail-checkout');
    // Capture the app's payment UI and PDF using the same basket. Backend
    // quote and ledger writes are outside this offline presentation fixture.
    final cart = tester
        .widgetList<CartItemTile>(find.byType(CartItemTile))
        .map((tile) => tile.item)
        .toList();
    final displayedTotal =
        tester.widget<PosCheckoutPanel>(find.byType(PosCheckoutPanel)).total;
    final payment = showPaymentSheet(navigator.currentState!.overlay!.context,
        total: displayedTotal, initialChannel: SalesChannel.storefront);
    await tester.pumpAndSettle();
    final cash = find.widgetWithText(TextField, 'จำนวนเงินที่รับ');
    await tester.enterText(cash, '25');
    await tester.pumpAndSettle();
    expect(find.text('เงินทอน'), findsOneWidget);
    await save('retail-payment');
    await tester.tap(find.text('ยืนยันการชำระเงิน'));
    await tester.pumpAndSettle();
    final result = (await payment)!;
    expect(result.paid, displayedTotal);
    tester.view.physicalSize = const Size(390, 660);
    await tester.pumpAndSettle();
    expect(find.text('ตะกร้า 2 หน่วย · ฿25.00').hitTestable(), findsOneWidget);
    await save('retail-checkout-mobile');

    await mount(
        Scaffold(
            body: ProductCatalog(
                products: retail,
                categories: const ['เครื่องดื่ม', 'ขนม', 'ของใช้'],
                preferenceKey: 'stock-demo',
                onEdit: (_) {},
                onReceiveStock: (_) {},
                showInventory: true)),
        const Size(590, 400));
    expect(find.text(retail.first.name), findsWidgets);
    await save('retail-stock');
    final saleItems = [
      for (final item in cart)
        SaleItem(
            productId: item.product.id,
            productName: item.product.name,
            category: item.product.category,
            price: item.unitPrice,
            quantity: item.quantity,
            subtotal: item.subtotal),
    ];
    final cashTotal = saleItems.fold<double>(0, (sum, i) => sum + i.subtotal);
    final bill = Sale(
        id: 'retail-demo',
        receiptNo: 'DEMO-0001',
        receiptProfile: const ReceiptProfile(name: 'มินิมาร์ทสาธิต'),
        items: saleItems,
        total: cashTotal,
        discount: 0,
        paid: result.paid,
        paymentMethod: result.method,
        change: result.paid - cashTotal,
        createdAt: DateTime(2026, 11, 24, 9),
        salesChannel: result.salesChannel);
    await mount(
        Scaffold(body: SalesInsights(sales: [bill])), const Size(590, 420));
    expect(find.textContaining('25.00'), findsWidgets);
    await save('retail-report');
    await tester.runAsync(() async {
      final pdf = await ReceiptGenerator.buildReceipt(bill,
          format: ReceiptGenerator.slip80);
      await File(
              '${Platform.environment["STORY_OUTPUT"]}/retail-receipt-1.2.84.pdf')
          .writeAsBytes(pdf);
    });
    const food = [
      Product(
          id: 'pasta',
          name: 'พาสต้ากุ้งและมะเขือเทศ',
          barcode: '',
          price: 80,
          stock: 20,
          category: 'อาหาร'),
      Product(
          id: 'spaghetti',
          name: 'สปาเกตตีซอสมะเขือเทศ',
          barcode: '',
          price: 70,
          stock: 20,
          category: 'อาหาร'),
    ];
    final items = [
      for (final p in food)
        TableOrderItem(
            id: p.id,
            productId: p.id,
            productName: p.name,
            price: p.price,
            quantity: p.id == 'pasta' ? 2 : 1,
            notes: p.id == 'pasta' ? 'ไม่ใส่พริก' : null)
    ];
    final order = ValueNotifier(TableOrder(
        id: 'demo',
        tableId: 'demo-table',
        tableName: '01',
        openedAt: DateTime(2026, 11, 22),
        items: [items.first.copyWith(kitchenStatus: KitchenStatus.sent)]));
    await mount(
        TableProductPicker(
            tableName: '01',
            products: Stream.value(food),
            order: order,
            save: (_, __) async => throw StateError('capture never saves'),
            checkout: (_) async {},
            chooseModifiers: (_, __) async => null),
        const Size(960, 640));
    expect(find.text('ขายที่โต๊ะ 01'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-product-spaghetti')));
    await tester.pumpAndSettle();
    expect(find.text('รายการใหม่ · ยังไม่บันทึก'), findsOneWidget);
    expect(find.textContaining('ส่งครัวแล้ว'), findsOneWidget);
    await save('restaurant-table');
    final total =
        items.fold<double>(0, (sum, item) => sum + item.price * item.quantity);
    showPaymentSheet(navigator.currentState!.overlay!.context,
        total: total,
        initialChannel: SalesChannel.dineIn,
        summary: [
          ...items.map((i) => '${i.productName} × ${i.quantity}'),
          'ค่าสินค้า ฿${total.toStringAsFixed(2)}',
          'ส่วนลด ฿0.00',
          'ค่าบริการ ฿0.00'
        ].join('\n'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await save('restaurant-bill');
    await tester.pumpWidget(const SizedBox.shrink());
    display.dispose();
    order.dispose();
  });
}
