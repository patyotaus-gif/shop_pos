import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';

void main() {
  test(
      'pickup time is independent of created/paid time and legacy orders remain readable',
      () {
    final created = DateTime.utc(2026, 10, 7, 2);
    final pickup = DateTime.utc(2026, 10, 8, 5);
    final order = ShopOrder.fromFirestore({
      'createdAt': Timestamp.fromDate(created),
      'pickupStartAt': Timestamp.fromDate(pickup),
      'pickupLabel': '08/10/2026 12:00–12:15 น.',
      'pickupMode': 'scheduled',
      'total': 50,
      'items': [
        {
          'productName': 'ข้าว',
          'price': 50,
          'quantity': 1,
          'modifiers': [
            {'optionName': 'ไข่ดาว'}
          ],
          'notes': 'ไม่เผ็ด'
        }
      ],
    }, 'o');
    expect(order.createdAt.toUtc(), created);
    expect(order.pickupStartAt!.toUtc(), pickup);
    expect(order.paidAt, isNull);
    expect(order.total, 50);
    expect(order.pickupDescription, contains('12:00–12:15'));
    expect(order.items.single.preparationNote, 'ไข่ดาว • ไม่เผ็ด');
    expect(ShopOrder.fromFirestore({'total': 10}, 'old').pickupDescription,
        isNull);
  });
}
