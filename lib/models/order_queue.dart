import 'order.dart';

enum OrderQueue { action, payment, preparation, ready, future, all }

extension OrderQueueLabel on OrderQueue {
  String get label => switch (this) {
        OrderQueue.action => 'ต้องทำต่อ',
        OrderQueue.payment => 'รอตรวจเงิน',
        OrderQueue.preparation => 'ต้องเตรียม',
        OrderQueue.ready => 'พร้อมรับ',
        OrderQueue.future => 'นัดล่วงหน้า',
        OrderQueue.all => 'ทั้งหมด',
      };
}

DateTime thaiDay(DateTime value) {
  final thai = value.toUtc().add(const Duration(hours: 7));
  return DateTime.utc(thai.year, thai.month, thai.day);
}

bool isFuturePickup(ShopOrder order, DateTime now) =>
    order.pickupStartAt != null &&
    thaiDay(order.pickupStartAt!).isAfter(thaiDay(now));
bool isActiveOrder(ShopOrder order) =>
    order.status != OrderStatus.completed &&
    order.status != OrderStatus.cancelled;
bool matchesQueue(ShopOrder order, OrderQueue queue, DateTime now) {
  final active = isActiveOrder(order);
  final future = isFuturePickup(order, now);
  return switch (queue) {
    OrderQueue.all => true,
    OrderQueue.action => active &&
        (!future ||
            order.bankMatchPending ||
            order.slipUrl != null &&
                order.status == OrderStatus.pendingPayment),
    OrderQueue.payment => order.status == OrderStatus.pendingPayment,
    OrderQueue.preparation => !future &&
        (order.status == OrderStatus.paid ||
            order.status == OrderStatus.accepted),
    OrderQueue.ready => order.status == OrderStatus.ready,
    OrderQueue.future => active && future,
  };
}

DateTime orderDueAt(ShopOrder order) => order.pickupStartAt ?? order.createdAt;
String? pickupUrgency(ShopOrder order, DateTime now) {
  if (!isActiveOrder(order) || order.pickupStartAt == null) return null;
  if ((order.pickupEndAt ?? order.pickupStartAt!).isBefore(now)) {
    return 'เลยเวลานัดรับ';
  }
  if (!order.pickupStartAt!.isAfter(now.add(const Duration(minutes: 30)))) {
    return 'ใกล้เวลานัดรับ';
  }
  return null;
}
