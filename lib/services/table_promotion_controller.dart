import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/table_order.dart';

typedef SyncTablePromotion = Future<TableOrder> Function(TableOrder order,
    {bool send, bool keepPreparedGifts, String reason});

/// Coalesces item edits; an older network result must never replace a newer bill.
class TablePromotionController extends ChangeNotifier {
  TablePromotionController(this.order, this.sync) {
    _schedule();
  }
  TableOrder order;
  final SyncTablePromotion sync;
  Object? error;
  bool busy = false;
  bool _disposed = false;
  Timer? _timer;
  Future<TableOrder?>? _running;
  String? _attempted;

  String _key(TableOrder o) => jsonEncode([
        o.id,
        o.status.name,
        o.promotion?['coupon']?['code'],
        o.items
            .where((i) => !i.isGift)
            .map((i) => [
                  i.id,
                  i.productId,
                  i.quantity,
                  i.unitPrice,
                  i.notes,
                  i.modifiers.map((m) => m.toMap()).toList()
                ])
            .toList()
      ]);

  void update(TableOrder value) {
    final changed = _key(value) != _key(order);
    final repriced = value.promotion?['revision'] != order.promotion?['revision'];
    order = value;
    if (changed || repriced) error = null;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        order.status != TableOrderStatus.open ||
        !order.items.any((i) => !i.isGift) ||
        order.promotionCurrent ||
        _attempted == _key(order)) {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 400), () => ensure());
  }

  Future<TableOrder?> ensure(
      {bool send = false,
      bool keepPreparedGifts = false,
      String reason = ''}) async {
    _timer?.cancel();
    final pending = _running;
    if (pending != null) await pending;
    if (_disposed) return null;
    // Serialize even when multiple callers awaited the same previous request.
    if (_running != null) {
      return ensure(
          send: send, keepPreparedGifts: keepPreparedGifts, reason: reason);
    }
    final operation =
        _run(send: send, keepPreparedGifts: keepPreparedGifts, reason: reason);
    _running = operation;
    try {
      return await operation;
    } finally {
      _running = null;
      if (!_disposed) _schedule();
    }
  }

  Future<TableOrder?> _run(
      {required bool send,
      required bool keepPreparedGifts,
      required String reason}) async {
    final requested = order;
    final key = _key(requested);
    _attempted = key;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await sync(requested,
          send: send, keepPreparedGifts: keepPreparedGifts, reason: reason);
      if (_disposed) return null;
      if (_key(order) != key) return null;
      order = result;
      if (result.status != TableOrderStatus.open) {
        error = StateError('บิลนี้ปิดหรือยกเลิกแล้ว กรุณากลับไปหน้าโต๊ะ');
        return null;
      }
      if (!result.promotionCurrent) {
        _attempted = null;
        error = StateError('รายการเปลี่ยน กำลังตรวจยอดใหม่');
        return null;
      }
      _attempted = _key(result);
      return result;
    } catch (e) {
      if (!_disposed && _key(order) == key) error = e;
      return null;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
