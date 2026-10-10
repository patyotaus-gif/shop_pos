import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/order_queue.dart';
import 'package:shop_pos/models/cash_close_check.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/screens/tables_screen.dart';
import 'package:shop_pos/widgets/mobile_sales_workspace.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';
import 'package:shop_pos/widgets/cash_close_blockers_dialog.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/screens/restaurant_sales_screen.dart';
import 'package:shop_pos/screens/pos_screen.dart';
import 'package:shop_pos/models/sale.dart';

ShopOrder order(OrderStatus status,
        {DateTime? pickup, bool slip = false, bool bankMatchPending = false}) =>
    ShopOrder(
        id: 'order',
        customerName: 'ลูกค้า',
        customerPhone: '',
        items: const [],
        total: 100,
        status: status,
        createdAt: DateTime.utc(2026, 10, 9, 10),
        pickupStartAt: pickup,
        bankMatchPending: bankMatchPending,
        slipUrl: slip ? 'https://example.test/slip' : null);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'restaurant entry keeps takeaway cart and defaults its sales channel correctly',
      (tester) async {
    expect((const RestaurantSalesScreen().takeaway as PosScreen).initialChannel,
        SalesChannel.takeaway);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: RestaurantSalesScreen(
                dineIn: Text('รายการโต๊ะ'), takeaway: _CounterCart()))));
    expect(find.text('รายการโต๊ะ'), findsOneWidget);
    await tester.tap(find.text('กลับบ้าน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มรายการ 0'));
    await tester.pump();
    await tester.tap(find.text('กินที่ร้าน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กลับบ้าน'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มรายการ 1'), findsOneWidget);
  });
  test(
      'queues use Thailand day, retain future payments needing review and prioritize pickup',
      () {
    final now = DateTime.utc(2026, 10, 9, 16, 50);
    final tomorrow = DateTime.utc(2026, 10, 9, 17, 10);
    final future = order(OrderStatus.paid, pickup: tomorrow);
    expect(matchesQueue(future, OrderQueue.future, now), isTrue);
    expect(matchesQueue(future, OrderQueue.action, now), isFalse);
    expect(
        matchesQueue(
            order(OrderStatus.pendingPayment, pickup: tomorrow, slip: true),
            OrderQueue.action,
            now),
        isTrue);
    expect(
        matchesQueue(order(OrderStatus.completed, pickup: tomorrow),
            OrderQueue.future, now),
        isFalse);
    expect(
        matchesQueue(
            future, OrderQueue.action, DateTime.utc(2026, 10, 9, 17, 1)),
        isTrue);
    expect(
        pickupUrgency(
            order(OrderStatus.accepted,
                pickup: now.subtract(const Duration(minutes: 1))),
            now),
        'เลยเวลานัดรับ');
    expect(
        pickupUrgency(order(OrderStatus.completed, pickup: now), now), isNull);
    final sorted = [future, order(OrderStatus.accepted, pickup: now)]
      ..sort((a, b) => orderDueAt(a).compareTo(orderDueAt(b)));
    expect(sorted.first.status, OrderStatus.accepted);
  });

  test(
      'three order groups retain every status exactly once, including overdue work',
      () {
    final now = DateTime.utc(2026, 10, 9, 16, 50);
    final tomorrow = DateTime.utc(2026, 10, 9, 17, 10);
    for (final status in OrderStatus.values) {
      for (final pickup in [
        null,
        now.subtract(const Duration(days: 1)),
        now,
        tomorrow
      ]) {
        for (final slip in [false, true]) {
          for (final bank in [false, true]) {
            final item = order(status,
                pickup: pickup, slip: slip, bankMatchPending: bank);
            final groups = OrderQueue.values
                .where((q) => matchesQueue(item, q, now))
                .toList();
            expect(groups, hasLength(1),
                reason: '$status / $pickup / $slip / $bank');
            if (status == OrderStatus.completed ||
                status == OrderStatus.cancelled) {
              expect(groups.single, OrderQueue.history);
            } else if (pickup == tomorrow &&
                !bank &&
                !(slip && status == OrderStatus.pendingPayment)) {
              expect(groups.single, OrderQueue.future);
            } else {
              expect(groups.single, OrderQueue.action);
            }
          }
        }
      }
    }
  });

  testWidgets(
      'table loading failure cannot masquerade as no tables and retry recovers',
      (tester) async {
    final source = StreamController<List<RestaurantTable>>();
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(home: TablesScreen(loadTables: () {
      attempts++;
      return attempts == 1 ? source.stream : Stream.value([]);
    })));
    source.addError(StateError('network'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีโต๊ะ'), findsNothing);
    expect(find.textContaining('โหลดโต๊ะไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีโต๊ะ'), findsOneWidget);
    expect(attempts, 2);
    unawaited(source.close());
  });

  testWidgets('phone keeps catalog mounted and basket quantity when switching',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var count = 0;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, set) => MobileSalesWorkspace(
                      itemCount: count,
                      total: count * 10,
                      catalog: ListView(children: [
                        FilledButton(
                            onPressed: () => set(() => count++),
                            child: const Text('น้ำดื่ม'))
                      ]),
                      basket: Column(children: [
                        Expanded(child: Text('จำนวน $count')),
                        PosCheckoutPanel(
                            compact: true,
                            subtotal: count * 10,
                            discount: 0,
                            total: count * 10,
                            hasItems: count > 0,
                            canDebt: false,
                            canDiscount: false,
                            onCheckout: () {},
                            onDebt: () {},
                            onDiscount: () {})
                      ]),
                    )))));
    await tester.tap(find.text('น้ำดื่ม'));
    await tester.pump();
    await tester.tap(find.text('น้ำดื่ม'));
    await tester.pump();
    await tester.tap(find.textContaining('ตะกร้า 2 ชิ้น'));
    await tester.pumpAndSettle();
    expect(find.text('จำนวน 2'), findsOneWidget);
    expect(find.text('ชำระเงิน'), findsOneWidget);
    await tester.tap(find.text('เลือกสินค้าต่อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('น้ำดื่ม'));
    await tester.pump();
    expect(find.textContaining('ตะกร้า 3 ชิ้น'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pinned shortcut persists per shop and cannot expose staff actions',
      (tester) async {
    Widget app(String shop, {bool staff = false}) => MaterialApp(
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: PosCheckoutPanel(
                    preferenceKey: 'shortcut:$shop',
                    compact: true,
                    subtotal: 100,
                    discount: 0,
                    total: 100,
                    hasItems: true,
                    canDebt: !staff,
                    canDiscount: !staff,
                    onCheckout: () {},
                    onDiscount: () {},
                    onDebt: () {}))));
    await tester.pumpWidget(app('a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('checkout-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปักหมุดปุ่มขายเชื่อ'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'ขายเชื่อ'), findsOneWidget);
    await tester.pumpWidget(app('b'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'ขายเชื่อ'), findsNothing);
    await tester.pumpWidget(app('a'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'ขายเชื่อ'), findsOneWidget);
    await tester.pumpWidget(app('a', staff: true));
    await tester.pumpAndSettle();
    expect(find.text('ขายเชื่อ'), findsNothing);
    expect(find.byKey(const ValueKey('checkout-more')), findsNothing);
  });

  testWidgets(
      'daily-close issue opens the exact record rather than a generic list',
      (tester) async {
    CashCloseIssue? opened;
    final issue = CashCloseIssue(
        type: 'unfinishedOrder',
        id: 'order-123',
        label: 'คุณเอ',
        message: 'รอรับสินค้า');
    await tester.pumpWidget(MaterialApp(
        home: CashCloseBlockersDialog(
            check: CashCloseCheck(
                canClose: false,
                closed: false,
                issueCount: 1,
                futureOrderCount: 0,
                issues: [issue]),
            onIssue: (value) => opened = value)));
    await tester.tap(find.text('รอรับสินค้า'));
    expect(opened?.id, 'order-123');
    expect(find.text('ปิดรอบ'), findsNothing);
  });

  testWidgets(
      'short landscape and enlarged text can browse then reach checkout',
      (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: MobileSalesWorkspace(
          itemCount: 2,
          total: 100,
          catalog: CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Column(
                    children: List.generate(
                        3,
                        (_) => const SizedBox(
                            height: 64, child: Text('ค้นหาและหมวดหมู่'))))),
            SliverFillRemaining(
                child: ListView(children: const [Text('น้ำดื่ม')]))
          ]),
          basket: Column(children: [
            const Expanded(child: Text('สินค้า 2 ชิ้น')),
            PosCheckoutPanel(
                compact: true,
                subtotal: 100,
                total: 100,
                discount: 0,
                hasItems: true,
                canDiscount: true,
                canDebt: true,
                onCheckout: () {},
                onDebt: () {},
                onDiscount: () {})
          ]),
        ))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.textContaining('ตะกร้า 2 ชิ้น'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('checkout-pay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('checkout-pay')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CounterCart extends StatefulWidget {
  const _CounterCart();
  @override
  State<_CounterCart> createState() => _CounterCartState();
}

class _CounterCartState extends State<_CounterCart> {
  int count = 0;
  @override
  Widget build(BuildContext context) => TextButton(
      onPressed: () => setState(() => count++),
      child: Text('เพิ่มรายการ $count'));
}
