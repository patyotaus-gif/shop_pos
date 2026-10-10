import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/screens/tables_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/theme/operational_colors.dart';
import 'package:shop_pos/widgets/order_summary_card.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';
import 'package:shop_pos/widgets/product_image.dart';

ShopOrder exampleOrder({String method = 'promptpay'}) => ShopOrder(
    id: 'o1',
    customerName: 'คุณสมศรี ลูกค้านัดรับอาหาร',
    customerPhone: '0812345678',
    items: List.generate(
        4,
        (i) => OrderItem(
            productId: '$i',
            productName: 'ข้าวกะเพราหมูสับไข่ดาวพิเศษ $i',
            price: 250,
            quantity: 1,
            preparationNote: i == 3 ? 'ไม่ใส่ถั่ว' : '')),
    total: 1000,
    finalAmount: 1000.91,
    paymentMethod: method,
    status: OrderStatus.pendingPayment,
    createdAt: DateTime(2026, 10, 10, 11),
    pickupLabel: '10 ต.ค. 12:00–12:30',
    orderType: 'takeaway',
    bankMatchPending: true,
    autoConfirmed: true,
    slipUrl: 'https://example.test/slip');

void main() {
  setUpAll(() => initializeDateFormatting('th_TH'));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'order summary keeps evidence and exact amount before confirmation; details and secondary actions remain reachable',
      (tester) async {
    var slip = 0, ticket = 0, kitchen = 0, paid = 0;
    for (final method in ['promptpay', 'stripe']) {
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: OrderSummaryCard(
                      key: ValueKey(method),
                      order: exampleOrder(method: method),
                      onSlip: () => slip++,
                      onTicket: () => ticket++,
                      onKitchen: () => kitchen++,
                      actions: FilledButton(
                          onPressed: () => paid++,
                          child: const Text('ได้รับเงินแล้ว')))))));
      expect(find.text(method == 'stripe' ? '฿1,000.00' : '฿1,000.91'),
          findsOneWidget);
      expect(find.textContaining('โปรดตรวจเงินเข้า'), findsOneWidget);
      expect(find.textContaining('โทร 081'), findsNothing);
      expect(find.text('ไม่ใส่ถั่ว'), findsNothing);
      await tester.tap(find.text('ดูสลิปการโอน'));
      expect(paid, 0);
      await tester.ensureVisible(find.text('รายละเอียด · ดูครบ 4 รายการ'));
      await tester.tap(find.text('รายละเอียด · ดูครบ 4 รายการ'));
      await tester.pumpAndSettle();
      expect(find.text('ไม่ใส่ถั่ว'), findsOneWidget);
      expect(find.text('โทร 0812345678'), findsOneWidget);
      expect(find.text('ยืนยันอัตโนมัติ'), findsOneWidget);
      await tester.ensureVisible(find.text('ใบงาน / พิมพ์ / PDF'));
      await tester.tap(find.text('ใบงาน / พิมพ์ / PDF'));
      await tester.ensureVisible(find.text('จอครัว / พิมพ์ที่ครัว'));
      await tester.tap(find.text('จอครัว / พิมพ์ที่ครัว'));
      expect(tester.takeException(), isNull);
    }
    expect(slip, 2);
    expect(ticket, 2);
    expect(kitchen, 2);
    expect(paid, 0);
  });

  testWidgets(
      'phone and tablet order cards and tables fit enlarged text in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final theme in [PokpokTheme.light(), PokpokTheme.dark()]) {
        Widget app(Widget child) => MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: child);
        await tester.pumpWidget(app(Scaffold(
            body: ListView(children: [
          OrderSummaryCard(
              order: exampleOrder(),
              onSlip: () {},
              onTicket: () {},
              urgency: 'ใกล้เวลานัดรับ',
              initiallyExpanded: true),
        ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(app(TablesScreen(
            loadTables: () => Stream.value([
                  for (final status in TableStatus.values)
                    RestaurantTable(
                        id: status.name,
                        name: 'โต๊ะริมหน้าต่าง 12',
                        capacity: 4,
                        section: 'ห้องปรับอากาศ',
                        status: status,
                        createdAt: DateTime(2026, 10, 10)),
                ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
      'pinned checkout shares one action row on phone and fits with total on tablet',
      (tester) async {
    SharedPreferences.setMockInitialValues({'shortcut:a': 'discount'});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: PosCheckoutPanel(
                      preferenceKey: 'shortcut:a',
                      compact: true,
                      subtotal: 1000,
                      total: 1000,
                      discount: 0,
                      hasItems: true,
                      canDiscount: true,
                      canDebt: true,
                      onCheckout: () {},
                      onDiscount: () {},
                      onDebt: () {})))));
      await tester.pumpAndSettle();
      final pin = tester.getRect(find.byKey(const ValueKey('checkout-pinned')));
      final pay = tester.getRect(find.byKey(const ValueKey('checkout-pay')));
      expect(pin.center.dy, closeTo(pay.center.dy, 1));
      expect(pin.height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(PosCheckoutPanel)).height,
          lessThanOrEqualTo(width < 500 ? 132 : 80));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'compact cart retains controls and differentiated no-photo products',
      (tester) async {
    const product = Product(
        id: 'p',
        name: 'ชาเย็น',
        category: 'เครื่องดื่ม',
        barcode: '',
        price: 1000,
        stock: 10);
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: Column(children: [
          SizedBox(
              width: 390,
              child: CartItemTile(
                  item: const CartItem(product: product),
                  onRemove: () {},
                  onQtyChanged: (_) {})),
          const SizedBox(
              width: 160, height: 130, child: ProductImage(product: product)),
        ]))));
    expect(find.text('฿1,000.00'), findsOneWidget);
    expect(tester.getCenter(find.text('฿1,000.00')).dy,
        closeTo(tester.getCenter(find.byTooltip('เพิ่มจำนวน')).dy, 1));
    expect(tester.getSize(find.byType(CartItemTile)).height, lessThan(150));
    expect(find.byIcon(Icons.local_drink_outlined), findsOneWidget);
    expect(
        find.text(product.name.characters.take(3).toString()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'status labels retain strong foreground contrast in light and dark themes',
      (tester) async {
    for (final theme in [PokpokTheme.light(), PokpokTheme.dark()]) {
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            for (final tone in OperationalTone.values) {
              final colors = OperationalColors.of(context, tone);
              final luminances = [
                colors.foreground.computeLuminance(),
                colors.background.computeLuminance()
              ]..sort();
              expect((luminances.last + 0.05) / (luminances.first + 0.05),
                  greaterThanOrEqualTo(4.5),
                  reason: '$tone ${theme.brightness}');
            }
            return const SizedBox();
          })));
    }
  });
}
