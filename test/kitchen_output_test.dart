import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/services/kitchen_print_service.dart';

ShopOrder online(String id, OrderStatus status,
        {DateTime? statusUpdatedAt, DateTime? pickupStartAt}) =>
    ShopOrder(
        id: id,
        customerName: 'ลูกค้า',
        customerPhone: '0812345678',
        items: [
          OrderItem(
              productId: id,
              productName: 'อาหาร$id',
              price: 50,
              quantity: 2,
              preparationNote: 'ไม่เผ็ด • เพิ่มไข่')
        ],
        total: 100,
        finalAmount: 100.05,
        status: status,
        createdAt: DateTime(2026),
        statusUpdatedAt: statusUpdatedAt,
        pickupStartAt: pickupStartAt,
        pickupLabel: '09/10/2026 12:00–12:15 น.');
TableOrder table(String id,
        {DateTime? closedAt,
        TableOrderStatus status = TableOrderStatus.closed}) =>
    TableOrder(
        id: id,
        tableId: id,
        tableName: id,
        status: status,
        closedAt: closedAt,
        openedAt: DateTime(2026),
        items: [
          TableOrderItem(
              id: 'i',
              productId: 'rice',
              productName: 'อาหารโต๊ะ$id',
              price: 50,
              quantity: 1,
              kitchenStatus: KitchenStatus.sent)
        ]);
void main() {
  testWidgets(
      'cash close archives finished tickets and keeps open work and future pickups',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final closing = StreamController<DateTime?>();
    addTearDown(closing.close);
    final cutoff = DateTime(2026, 10, 13, 9);
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      orders: Stream.value([
        table('previous', closedAt: cutoff),
        table('current', closedAt: cutoff.add(const Duration(minutes: 30))),
        table('active', status: TableOrderStatus.open),
      ]),
      onlineOrders: Stream.value([
        online('previous-online', OrderStatus.completed,
            statusUpdatedAt: cutoff.subtract(const Duration(minutes: 1))),
        online('current-online', OrderStatus.completed,
            statusUpdatedAt: cutoff.add(const Duration(minutes: 30))),
        online('future-pickup', OrderStatus.paid,
            pickupStartAt: cutoff.add(const Duration(days: 1))),
      ]),
      settings: Stream.value({'kitchenOutput': 'printer'}),
      lastClosedAt: closing.stream,
    )));
    closing.add(cutoff);
    await tester.pumpAndSettle();
    expect(find.text('ดูใบงานรอบก่อน (2)'), findsOneWidget);
    expect(find.text('ใบงานที่ปิดบิลหรือเสร็จแล้ว (2)'), findsOneWidget);
    expect(find.text('อาหารโต๊ะactive'), findsOneWidget);
    expect(find.text('อาหารfuture-pickup × 2'), findsOneWidget);
    expect(find.text('อาหารโต๊ะprevious'), findsNothing);
    await tester.tap(find.text('ใบงานที่ปิดบิลหรือเสร็จแล้ว (2)'));
    await tester.pumpAndSettle();
    expect(find.text('อาหารโต๊ะcurrent'), findsOneWidget);
    expect(find.text('อาหารcurrent-online × 2'), findsOneWidget);
    expect(find.text('อาหารprevious-online × 2'), findsNothing);
    await tester.tap(find.text('ดูใบงานรอบก่อน (2)'));
    await tester.pumpAndSettle();
    expect(find.text('อาหารโต๊ะprevious'), findsOneWidget);
    expect(find.text('อาหารprevious-online × 2'), findsOneWidget);
    closing.add(cutoff.add(const Duration(hours: 1)));
    await tester.pumpAndSettle();
    expect(find.text('ดูใบงานรอบก่อน (4)'), findsOneWidget);
    expect(find.text('อาหารโต๊ะprevious'), findsNothing);
    expect(find.text('อาหารโต๊ะcurrent'), findsNothing);
    expect(find.text('อาหารcurrent-online × 2'), findsNothing);
    expect(find.text('อาหารโต๊ะactive'), findsOneWidget);
    expect(find.text('อาหารfuture-pickup × 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'a closed round with only older tickets shows a clean queue and reversible history',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      orders: Stream.value([table('old')]),
      settings: Stream.value({'kitchenOutput': 'printer'}),
      lastClosedAt: Stream.value(DateTime(2026, 10, 13)),
    )));
    await tester.pumpAndSettle();
    expect(find.text('ไม่มีงานครัวที่กำลังดำเนินการ'), findsOneWidget);
    expect(find.text('อาหารโต๊ะold'), findsNothing);
    await tester.tap(find.text('ดูใบงานรอบก่อน (1)'));
    await tester.pumpAndSettle();
    expect(find.text('อาหารโต๊ะold'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cash round loading errors do not claim an empty kitchen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
      orders: Stream.value([table('old')]),
      lastClosedAt: Stream.error(StateError('unavailable')),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดรอบปิดยอดไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsNothing);
  });
  testWidgets(
      'open table has a bill action and ready online order can be completed',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final old = table('active');
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([
              TableOrder(
                  id: old.id,
                  tableId: old.tableId,
                  tableName: old.tableName,
                  openedAt: old.openedAt,
                  items: old.items)
            ]),
            onlineOrders: Stream.value([online('ready', OrderStatus.ready)]))));
    await tester.pumpAndSettle();
    expect(find.text('ส่งมอบแล้ว / เสร็จสิ้น'), findsOneWidget);
    final queue = tester.state<ScrollableState>(find.byType(Scrollable).first);
    queue.position.jumpTo(queue.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('ไปที่บิลโต๊ะ / ปิดโต๊ะ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'kitchen combines paid online queue, options and pickup but hides unpaid orders',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([]),
            onlineOrders: Stream.value([
              online('paid', OrderStatus.paid),
              online('unpaid', OrderStatus.pendingPayment),
            ]))));
    await tester.pumpAndSettle();
    expect(find.text('อาหารpaid × 2'), findsOneWidget);
    expect(find.text('อาหารunpaid × 2'), findsNothing);
    expect(find.text('ไม่เผ็ด • เพิ่มไข่'), findsOneWidget);
    expect(find.textContaining('12:00–12:15'), findsOneWidget);
    expect(find.text('เริ่มเตรียม'), findsOneWidget);
  });
  testWidgets(
      'printer mode separates closed unprinted history from active work',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([table('waiting'), table('done')]),
            settings: Stream.value({'kitchenOutput': 'printer'}),
            printJobs: Stream.value({
              'table-done': {
                'status': 'printed',
                'printedKeys': ['x']
              },
            }))));
    await tester.pumpAndSettle();
    expect(find.text('อาหารโต๊ะwaiting'), findsNothing);
    expect(find.text('ไม่มีงานครัวที่กำลังดำเนินการ'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('อาหารโต๊ะwaiting'), findsOneWidget);
    expect(find.text('อาหารโต๊ะdone'), findsNothing);
    final queue = tester.state<ScrollableState>(find.byType(Scrollable).first);
    queue.position.jumpTo(queue.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('พิมพ์รายการใหม่'), findsOneWidget);
    expect(find.text('รอพิมพ์'), findsOneWidget);
    expect(find.textContaining('เปิดมา'), findsNothing);
  });
  testWidgets(
      'unconfirmed kitchen setting times out and late completion cannot claim success',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([]),
            saveOutput: (_) {
              calls++;
              return pending.future;
            })));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เครื่องพิมพ์ครัว'));
    await tester.pump();
    expect(find.text('กำลังบันทึกวิธีรับงานครัว'), findsOneWidget);
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('ยังยืนยันผลไม่ได้'), findsOneWidget);
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('บันทึกวิธีรับงานครัวแล้ว'), findsNothing);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
  });
  testWidgets('kitchen output choices and online ticket fit a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([]),
            onlineOrders: Stream.value([online('paid', OrderStatus.paid)]),
            settings: Stream.value({'kitchenOutput': 'printer'}))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('จอครัว'), findsOneWidget);
    expect(find.text('เครื่องพิมพ์ครัว'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('kitchen PDF uses bundled Thai fonts and supports long tickets',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await KitchenPrintService.buildTicket({
      'jobId': 'online-test',
      'title': 'รับกลับบ้าน',
      'customerName': 'ลูกค้า',
      'pickupLabel': '12:00–12:15',
      'reprint': true,
      'lines': List.generate(
          60,
          (i) =>
              {'name': 'ข้าวกะเพราไข่ดาว $i', 'quantity': 2, 'note': 'ไม่เผ็ด'})
    });
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
