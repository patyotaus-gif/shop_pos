import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/services/kitchen_print_service.dart';

ShopOrder online(String id, OrderStatus status) => ShopOrder(
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
    pickupLabel: '09/10/2026 12:00–12:15 น.');
TableOrder table(String id) => TableOrder(
        id: id,
        tableId: id,
        tableName: id,
        status: TableOrderStatus.closed,
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
      'printer mode retains closed unprinted tickets and hides acknowledged closed tickets',
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
    expect(find.text('อาหารโต๊ะwaiting'), findsOneWidget);
    expect(find.text('อาหารโต๊ะdone'), findsNothing);
    expect(find.text('พิมพ์รายการใหม่'), findsOneWidget);
    expect(find.text('รอพิมพ์'), findsOneWidget);
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
