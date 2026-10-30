import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

/// Read-only polling. Errors remain visible until a fresh snapshot arrives.
/// Cancellation/session changes discard in-flight results and stop timers.
Stream<T> recoveringPoll<T>({
  required Future<T> Function() fetch,
  required bool Function() active,
  Duration interval = const Duration(seconds: 5),
  Duration timeout = const Duration(seconds: 20),
}) {
  late StreamController<T> controller;
  Timer? timer;
  var cancelled = false;
  var failures = 0;
  Future<void> poll() async {
    if (cancelled) return;
    if (!active()) {
      await controller.close();
      return;
    }
    var delay = interval;
    try {
      final value = await fetch().timeout(timeout);
      if (cancelled) return;
      if (!active()) {
        await controller.close();
        return;
      }
      failures = 0;
      controller.add(value);
    } catch (error, stack) {
      if (cancelled) return;
      if (!active()) {
        await controller.close();
        return;
      }
      controller.addError(error, stack);
      final retry = error is TimeoutException ||
          (error is FirebaseException &&
              const {
                'unavailable',
                'deadline-exceeded',
                'network-request-failed',
                'internal',
                'unknown',
                'resource-exhausted',
              }.contains(error.code));
      if (!retry) {
        await controller.close();
        return;
      }
      failures = (failures + 1).clamp(1, 4);
      delay = Duration(
          milliseconds: (interval.inMilliseconds * (1 << (failures - 1)))
              .clamp(1, 30000));
    }
    if (!cancelled) timer = Timer(delay, poll);
  }

  controller = StreamController<T>(
      onListen: poll,
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      });
  return controller.stream;
}
