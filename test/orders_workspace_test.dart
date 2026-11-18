import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/screens/orders_screen.dart';
import 'package:shop_pos/services/shop_database.dart';

void main() {
  setUpAll(() => initializeDateFormatting('th_TH'));

  final orders = [
    for (final (number, name, menu, status) in [
      ('001', 'A', 'กาแฟ', OrderStatus.paid),
      ('002', 'B', 'ชาเย็น', OrderStatus.paid),
      ('003', 'C', 'โกโก้', OrderStatus.ready),
    ])
      ShopOrder(
        id: number,
        orderNumber: number,
        customerName: name,
        customerPhone: '',
        items: [
          OrderItem(productId: menu, productName: menu, price: 45, quantity: 1)
        ],
        total: 45,
        status: status,
        createdAt: DateTime.utc(2026, 11, 18, 4, int.parse(number)),
      ),
  ];

  for (final width in [390.0, 820.0, 1440.0]) {
    testWidgets('queue search, selection and ready handover at width $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shop = FakeFirebaseFirestore().collection('shops').doc('demo');
      ShopDatabase.overrideShop = shop;
      addTearDown(() => ShopDatabase.overrideShop = null);
      for (final order in orders) {
        await shop.collection('orders').doc(order.id).set({
          'orderNumber': order.orderNumber,
          'customerName': order.customerName,
          'status': order.status.name,
          'createdAt': order.createdAt,
          'total': order.total,
          'items': order.items.map((i) => i.toMap()).toList(),
        });
      }
      await tester.pumpWidget(const MaterialApp(home: OrdersScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('queue-001')), findsOneWidget);
      expect(find.byKey(const ValueKey('queue-003')), findsNothing);
      if (width >= 760) {
        await tester.tap(find.byKey(const ValueKey('queue-002')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('detail-002')), findsOneWidget);
      } else {
        expect(find.text('รับออเดอร์'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('queue-002')));
        await tester.pumpAndSettle();
        expect(find.text('รายละเอียดออเดอร์'), findsOneWidget);
        expect(find.text('รับออเดอร์'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'ชาเย็น');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-001')), findsNothing);
      expect(find.byKey(const ValueKey('queue-002')), findsOneWidget);
      await tester.ensureVisible(find.text('พร้อมรับ').first);
      await tester.tap(find.text('พร้อมรับ').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('queue-003')), findsOneWidget);
      expect(find.text('รับของแล้ว'),
          width >= 760 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
