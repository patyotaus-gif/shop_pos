import 'dart:async';

/// Replaces a calendar-day query at local midnight, even if its screen stays open.
/// Uses the actual date again after a delayed timer (for example app suspension).
Stream<T> watchDaily<T>(
  Stream<T> Function(DateTime day) query, {
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  return Stream<T>.multi((controller) {
    Timer? timer;
    StreamSubscription<T>? subscription;
    var generation = 0;
    var cancelled = false;

    void refresh() {
      if (cancelled) return;
      final time = clock();
      final day = DateTime(time.year, time.month, time.day);
      final nextDay = DateTime(time.year, time.month, time.day + 1);
      final current = ++generation;
      timer = Timer(nextDay.difference(time), refresh);
      subscription?.cancel();
      try {
        subscription = query(day).listen(
          (value) {
            if (!cancelled && generation == current) controller.add(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!cancelled && generation == current) {
              controller.addError(error, stack);
            }
          },
        );
      } catch (error, stack) {
        controller.addError(error, stack);
      }
    }

    controller.onCancel = () {
      cancelled = true;
      timer?.cancel();
      subscription?.cancel();
    };
    refresh();
  });
}
