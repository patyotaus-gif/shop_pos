import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/order_modifier.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

TableOrder chefTicket({int count = 1, String name = 'A1'}) => TableOrder(
      id: 'chef-table',
      tableId: 'a1',
      tableName: name,
      openedAt: DateTime(2026, 10, 30, 12),
      items: List.generate(
          count,
          (i) => TableOrderItem(
                id: 'item-$i',
                productId: 'food',
                productName: 'อาหารจานที่ $i',
                price: 50,
                quantity: 2,
                kitchenStatus: KitchenStatus.sent,
                notes: 'แพ้ถั่ว ไม่ใส่ถั่วและน้ำมันถั่ว',
                modifiers: const [
                  OrderModifier(
                      groupId: 'egg',
                      groupName: 'ไข่',
                      optionId: 'extra',
                      optionName: 'เพิ่มไข่ดาว',
                      priceAdjust: 10)
                ],
              )),
    );

ShopOrder chefOnline(String id, OrderStatus status, {DateTime? pickup}) =>
    ShopOrder(
      id: id,
      orderNumber: '261030-$id',
      customerName: 'ลูกค้าทดสอบ',
      customerPhone: '',
      createdAt: DateTime(2026, 10, 30, 12),
      pickupStartAt: pickup,
      status: status,
      total: 50,
      items: [
        OrderItem(
            productId: id,
            productName: id,
            price: 50,
            quantity: 1,
            preparationNote: 'ไม่ใส่พริก')
      ],
    );

void main() {
  tearDown(() => ShopDatabase.overrideShop = null);

  testWidgets(
      'chef marks a real table item ready without billing or stock changes',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('chef-test');
    ShopDatabase.overrideShop = shop;
    final ticket = chefTicket();
    await shop.collection('products').doc('food').set({'stock': 10});
    final ref = shop.collection('tableOrders').doc(ticket.id);
    await ref.set(ticket.toFirestore());
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      orders: TableService.watchKitchenOrders(),
      markReady: (orderId, itemId) async {
        final current =
            TableOrder.fromFirestore((await ref.get()).data()!, orderId);
        await ref.update({
          'items': current.items
              .map((i) => i.id == itemId
                  ? i.copyWith(kitchenStatus: KitchenStatus.ready).toMap()
                  : i.toMap())
              .toList()
        });
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('โน้ต: แพ้ถั่ว ไม่ใส่ถั่วและน้ำมันถั่ว'), findsOneWidget);
    expect(find.text('• เพิ่มไข่ดาว'), findsOneWidget);
    await tester.tap(find.text('อาหารจานที่ 0'));
    await tester.pumpAndSettle();
    expect((await ref.get()).data()!['items'][0]['kitchenStatus'], 'ready');
    expect(find.text('พร้อมเสิร์ฟทั้งหมด'), findsOneWidget);
    expect(
        (await shop.collection('products').doc('food').get()).data()!['stock'],
        10);
    expect((await shop.collection('sales').get()).docs, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live queue receives a ticket and removes a cancelled ticket',
      (tester) async {
    final stream = StreamController<List<TableOrder>>();
    addTearDown(stream.close);
    await tester
        .pumpWidget(MaterialApp(home: KitchenScreen(orders: stream.stream)));
    stream.add([]);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsOneWidget);
    stream.add([chefTicket()]);
    await tester.pumpAndSettle();
    expect(find.text('อาหารจานที่ 0'), findsOneWidget);
    final old = chefTicket();
    stream.add([
      TableOrder(
          id: old.id,
          tableId: old.tableId,
          tableName: old.tableName,
          openedAt: old.openedAt,
          items: old.items,
          status: TableOrderStatus.cancelled)
    ]);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsOneWidget);
    expect(find.text('อาหารจานที่ 0'), findsNothing);
  });

  testWidgets(
      'online lifecycle shows the next action and removes completed work',
      (tester) async {
    final stream = StreamController<List<ShopOrder>>();
    addTearDown(stream.close);
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([]), onlineOrders: stream.stream)));
    for (final stage in [
      (OrderStatus.paid, 'เริ่มเตรียม'),
      (OrderStatus.accepted, 'พร้อมรับ / เสิร์ฟแล้ว'),
      (OrderStatus.ready, 'ส่งมอบแล้ว / เสร็จสิ้น'),
    ]) {
      stream.add([chefOnline('online', stage.$1)]);
      await tester.pumpAndSettle();
      expect(find.text(stage.$2), findsOneWidget);
    }
    stream.add([chefOnline('online', OrderStatus.completed)]);
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'tablet long tickets keep the last food reachable (${dark ? 'dark' : 'light'})',
        (tester) async {
      tester.view.physicalSize = const Size(1480, 924);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
        home: KitchenScreen(orders: Stream.value([chefTicket(count: 20)])),
      ));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('อาหารจานที่ 19'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('อาหารจานที่ 19').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
