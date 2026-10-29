import 'order.dart';

enum OrderQueue { confirmation, preparing, future, history }

extension OrderQueueLabel on OrderQueue {
  String get label => switch (this) {
        OrderQueue.confirmation => 'รอยืนยัน',
        OrderQueue.preparing => 'กำลังเตรียม',
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
  final needsConfirmation = needsReview ||
      order.status == OrderStatus.pendingPayment ||
      order.status == OrderStatus.paid;
  // Once work starts, the operational queue takes precedence over pickup day.
  final started =
      order.status == OrderStatus.accepted || order.status == OrderStatus.ready;
  final current = active && (!future || needsReview || started);
  return switch (queue) {
    OrderQueue.confirmation => current && needsConfirmation,
    OrderQueue.preparing => current && !needsConfirmation,
    OrderQueue.future => active && future && !needsReview && !started,
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
