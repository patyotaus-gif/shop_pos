import 'order.dart';

enum OrderQueue { confirmation, preparing, ready, future, history }

extension OrderQueueLabel on OrderQueue {
  String get label => switch (this) {
        OrderQueue.confirmation => 'รอยืนยัน',
        OrderQueue.preparing => 'กำลังเตรียม',
        OrderQueue.ready => 'พร้อมรับ',
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
  return orderQueueFor(order, now) == queue;
}

OrderQueue orderQueueFor(ShopOrder order, DateTime now) {
  if (!isActiveOrder(order)) return OrderQueue.history;
  if (order.bankMatchPending) return OrderQueue.confirmation;
  if (order.status == OrderStatus.ready) return OrderQueue.ready;
  if (order.status == OrderStatus.accepted) return OrderQueue.preparing;
  final needsReview =
      order.status == OrderStatus.pendingPayment && order.slipUrl != null;
  if (isFuturePickup(order, now) && !needsReview) return OrderQueue.future;
  return OrderQueue.confirmation;
}

bool matchesOrderSearch(ShopOrder order, String query) {
  final term = query.trim().toLowerCase();
  return term.isEmpty ||
      [
        order.displayLabel,
        order.displayNumber,
        order.customerName,
        ...order.items.map((item) => item.productName),
      ].any((value) => value.toLowerCase().contains(term));
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
