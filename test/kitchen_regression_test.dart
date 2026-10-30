import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'kitchen_chef_journey_test.dart' show chefTicket, chefOnline;

void main() {
  testWidgets(
      'settings disconnect recovers without resubscribing to the other streams',
      (tester) async {
    final settings = StreamController<Map<String, dynamic>>();
    addTearDown(settings.close);
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      orders: Stream.value([chefTicket()]),
      settings: settings.stream,
    )));
    settings.add({});
    await tester.pumpAndSettle();
    expect(find.text('อาหารจานที่ 0'), findsOneWidget);
    settings.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    settings.add({});
    await tester.pumpAndSettle();
    expect(find.text('อาหารจานที่ 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  setUpAll(() async {
    final font = FontLoader(PokpokTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    await font.load();
  });
  testWidgets(
      'paid unfinished food survives closing the drawer and can be marked ready',
      (tester) async {
    final ticket = chefTicket();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      lastClosedAt: Stream.value(DateTime(2026, 10, 31)),
      orders: Stream.value([
        TableOrder(
            id: ticket.id,
            tableId: ticket.tableId,
            tableName: ticket.tableName,
            openedAt: ticket.openedAt,
            status: TableOrderStatus.closed,
            items: ticket.items)
      ]),
      markReady: (order, item) async {
        expect(order, ticket.id);
        expect(item, ticket.items.single.id);
        calls++;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('ชำระแล้ว • ยังมีอาหารที่ต้องเตรียม'), findsOneWidget);
    expect(find.text('ไปที่บิลโต๊ะ / ปิดโต๊ะ'), findsNothing);
    await tester.tap(find.text('อาหารจานที่ 0'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('large text and a long table name keep food reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: KitchenScreen(
            orders: Stream.value([
          chefTicket(
              count: 20,
              name:
                  'ห้องจัดเลี้ยงด้านใน โต๊ะครอบครัวและเพื่อน หมายเลข 123456789')
        ]))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('อาหารจานที่ 19'));
    await tester.pumpAndSettle();
    expect(find.text('อาหารจานที่ 19').hitTestable(), findsOneWidget);
  });
  testWidgets(
      'future pickups are separate from current tables and advance at Thai midnight',
      (tester) async {
    var now = DateTime.utc(2026, 10, 30, 16, 59);
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      now: () => now,
      orders: Stream.value([chefTicket()]),
      onlineOrders: Stream.value([
        chefOnline('tomorrow', OrderStatus.paid,
            pickup: DateTime.utc(2026, 10, 31, 5))
      ]),
    )));
    await tester.pumpAndSettle();
    expect(find.text('งานที่ต้องเตรียม (1)'), findsOneWidget);
    expect(find.text('tomorrow × 1'), findsNothing);
    await tester.ensureVisible(find.text('นัดรับวันถัดไป (1)'));
    await tester.tap(find.text('นัดรับวันถัดไป (1)'));
    await tester.pumpAndSettle();
    expect(find.text('tomorrow × 1'), findsOneWidget);
    now = DateTime.utc(2026, 10, 30, 17);
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('นัดรับวันถัดไป (1)'), findsNothing);
    await tester.ensureVisible(find.text('งานที่ต้องเตรียม (2)'));
    await tester.pumpAndSettle();
    expect(find.text('งานที่ต้องเตรียม (2)'), findsOneWidget);
  });
  testWidgets(
      'read error hides stale actions and a fresh snapshot restores them',
      (tester) async {
    final stream = StreamController<List<TableOrder>>();
    addTearDown(stream.close);
    await tester
        .pumpWidget(MaterialApp(home: KitchenScreen(orders: stream.stream)));
    stream.add([chefTicket()]);
    await tester.pumpAndSettle();
    expect(find.text('อาหารจานที่ 0'), findsOneWidget);
    stream.addError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(find.text('อาหารจานที่ 0'), findsNothing);
    stream.add([chefTicket()]);
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่'), findsNothing);
    expect(find.text('อาหารจานที่ 0'), findsOneWidget);
  });
}
