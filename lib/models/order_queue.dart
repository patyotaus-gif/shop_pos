import 'order.dart';

enum OrderQueue { action, future, history }

extension OrderQueueLabel on OrderQueue {
  String get label => switch (this) {
        OrderQueue.action => 'งานค้าง',
        OrderQueue.future => 'นัดล่วงหน้า',
        OrderQueue.history => 'ประวัติ',
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
  // Evidence requiring review stays actionable even for a future pickup.
  final needsReview = order.bankMatchPending ||
      order.slipUrl != null && order.status == OrderStatus.pendingPayment;
  return switch (queue) {
    OrderQueue.action => active && (!future || needsReview),
    OrderQueue.future => active && future && !needsReview,
    OrderQueue.history => !active,
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
