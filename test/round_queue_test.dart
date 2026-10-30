import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shop_pos/widgets/order_summary_card.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/services/sale_service.dart';

void main() {
  testWidgets('phone order card shows queue and reference without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final order = ShopOrder.fromFirestore({
      'orderNumber': '20261030-010',
      'queueNumber': '007',
      'queueSessionId': 's',
      'queueChannel': 'online',
      'items': [],
      'createdAt': Timestamp.now(),
    }, 'id');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: OrderSummaryCard(
                    order: order, onTicket: () {}, onSlip: () {})))));
    expect(find.text('ออนไลน์ 007'), findsOneWidget);
    expect(find.text('อ้างอิง 20261030-010'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
      'takeaway checkout shares the counter, replays and resets only per round',
      () async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('shop');
    await shop
        .collection('products')
        .doc('tea')
        .set({'name': 'Tea', 'stock': 20});
    Future<void> open(String id) async {
      await shop
          .collection('cashControl')
          .doc('current')
          .set({'sessionId': id});
      await shop.collection('cashSessions').doc(id).set({'status': 'open'});
    }

    Sale draft(String id, DateTime time) => Sale(
        id: id,
        items: const [
          SaleItem(
              productId: 'tea',
              productName: 'Tea',
              price: 20,
              quantity: 1,
              subtotal: 20)
        ],
        total: 20,
        discount: 0,
        paid: 20,
        change: 0,
        createdAt: time,
        salesChannel: SalesChannel.takeaway);
    await open('a');
    final first = await SaleService.commitSale(
        shop, draft('one', DateTime(2026, 10, 30, 23, 59)));
    expect(first.queue?.label, 'กลับบ้าน 001');
    expect(
        (await SaleService.commitSale(
                shop, draft('one', DateTime(2026, 10, 31))))
            .queue
            ?.label,
        'กลับบ้าน 001');
    // A staff checkout has already allocated 002 using the same server counter.
    // fake_cloud_firestore 3.1.0's Transaction.set drops SetOptions(merge:true).
    // Restore the control fields it incorrectly removes in MoneyLedger.recordSale.
    // The real Firestore integration suite separately verifies round persistence.
    await shop
        .collection('cashControl')
        .doc('current')
        .set({'sessionId': 'a'}, SetOptions(merge: true));
    await shop
        .collection('counters')
        .doc('queue-a-takeaway')
        .update({'seq': 2});
    final next = await SaleService.commitSale(
        shop, draft('two', DateTime(2026, 10, 31)));
    expect(next.queue?.label, 'กลับบ้าน 003');
    await shop.collection('cashSessions').doc('a').update({'status': 'closed'});
    await open('b');
    final reset = await SaleService.commitSale(
        shop, draft('three', DateTime(2026, 10, 31, 1)));
    expect(reset.queue?.label, 'กลับบ้าน 001');
    expect(reset.queue?.sessionId, 'b');
    expect(reset.receiptNo, isNot(first.receiptNo));
    expect((await shop.collection('sales').get()).size, 3);
    expect((await shop.collection('moneyMovements').get()).size, 3);
    expect(
        (await shop.collection('products').doc('tea').get()).data()?['stock'],
        17);
    expect(Sale.fromFirestore(reset.toFirestore(), 'copy').queue?.label,
        'กลับบ้าน 001');
  });
  test('closed or stale-round sales get no misleading current queue', () async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('shop');
    await shop
        .collection('products')
        .doc('tea')
        .set({'name': 'Tea', 'stock': 20});
    await shop.collection('cashControl').doc('current').set({
      'sessionId': 's',
      'openedAt': Timestamp.fromDate(DateTime(2026, 10, 31))
    });
    await shop.collection('cashSessions').doc('s').set({'status': 'open'});
    final sale = await SaleService.commitSale(
        shop,
        Sale(
            id: 'late',
            items: const [
              SaleItem(
                  productId: 'tea',
                  productName: 'Tea',
                  price: 20,
                  quantity: 1,
                  subtotal: 20)
            ],
            total: 20,
            discount: 0,
            paid: 20,
            change: 0,
            createdAt: DateTime(2026, 10, 30),
            salesChannel: SalesChannel.takeaway));
    expect(sale.queue, isNull);
    expect(
        (await shop.collection('counters').doc('queue-s-takeaway').get())
            .exists,
        isFalse);
  });
  test('order labels prefer tables and preserve legacy reference fallback', () {
    final data = <String, dynamic>{
      'orderNumber': '20261030-001',
      'queueNumber': '002',
      'queueSessionId': 's',
      'queueChannel': 'online',
      'items': [],
      'createdAt': Timestamp.now()
    };
    expect(ShopOrder.fromFirestore(data, 'id').displayLabel, 'ออนไลน์ 002');
    expect(
        ShopOrder.fromFirestore({...data, 'tableName': 'A1'}, 'id')
            .displayLabel,
        'โต๊ะ A1');
    data.remove('queueNumber');
    expect(ShopOrder.fromFirestore(data, 'id').displayLabel,
        'เลขออเดอร์ 20261030-001');
  });
}
