// Copy into test/ in a current checkout and set STORY_OUTPUT to a directory.
// All inputs are synthetic. No backend, sale or payment is created.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/services/sale_display_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/payment_sheet.dart';
import 'package:shop_pos/widgets/sales_insights.dart';
import 'package:shop_pos/widgets/pos_catalog.dart';
import 'package:shop_pos/widgets/product_catalog.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'package:shop_pos/widgets/sale_display_controls.dart';
import 'helpers/signed_out_firebase.dart';

void main() {
  setupSignedOutFirebase();
  testWidgets('capture retail catalog, stock and a matching table bill',
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
        await File('${Platform.environment["STORY_OUTPUT"]}/$name-1.2.83.png')
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
      for (final p in retail.take(2))
        SaleItem(
            productId: p.id,
            productName: p.name,
            category: p.category,
            price: p.price,
            quantity: 1,
            subtotal: p.price),
    ];
    final cashTotal = saleItems.fold<double>(0, (sum, i) => sum + i.subtotal);
    final bill = Sale(
        id: 'retail-demo',
        items: saleItems,
        total: cashTotal,
        discount: 0,
        paid: cashTotal,
        change: 0,
        createdAt: DateTime(2026, 11, 24, 9),
        salesChannel: SalesChannel.storefront);
    await mount(
        Scaffold(body: SalesInsights(sales: [bill])), const Size(590, 420));
    expect(find.textContaining('25.00'), findsWidgets);
    await save('retail-report');
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
        items: items));
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
