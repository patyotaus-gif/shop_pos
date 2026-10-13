import '../utils/stock_quantity.dart';
import 'dart:async';

/// Coalesces rapid taps; never overlaps writes for the same order line.
class QuantityEditQueue {
  QuantityEditQueue(
      {required num quantity,
      required this.save,
      required this.onChanged,
      required this.onError,
      this.delay = const Duration(milliseconds: 300)})
      : confirmed = quantity,
        target = quantity;
  final Future<void> Function(num expected, num target) save;
  final void Function() onChanged;
  final void Function(Object error) onError;
  final Duration delay;
  num confirmed;
  num target;
  Timer? _timer;
  bool _saving = false, _disposed = false;
  bool get busy => _saving || _timer != null;
  void change(num delta) {
    if (_disposed || (_saving && confirmed > 0 && target == 0)) return;
    target = stockRound(target + delta).clamp(0, 9999);
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      _flush();
    });
    onChanged();
  }

  void reconcile(num quantity) {
    if (!busy) {
      confirmed = quantity;
      target = quantity;
    }
  }

  Future<void> _flush() async {
    if (_saving || _disposed) return;
    _saving = true;
    onChanged();
    try {
      while (!_disposed && target != confirmed) {
        final sent = target;
        await save(confirmed, sent);
        confirmed = sent;
      }
    } catch (error) {
      target = confirmed;
      _timer?.cancel();
      _timer = null;
      if (!_disposed) onError(error);
    } finally {
      _saving = false;
      if (!_disposed) onChanged();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
