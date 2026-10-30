import 'package:fake_async/fake_async.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/utils/recovering_poll.dart';

void main() {
  test('transient read errors are visible and polling recovers', () {
    fakeAsync((clock) {
      var calls = 0;
      final values = <int>[], errors = <Object>[];
      final sub = recoveringPoll(
          active: () => true,
          fetch: () async {
            calls++;
            if (calls <= 2) {
              throw FirebaseException(
                  plugin: 'cloud_functions', code: 'unavailable');
            }
            return calls;
          }).listen(values.add, onError: errors.add);
      clock.flushMicrotasks();
      expect(errors.length, 1);
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(errors.length, 2);
      clock.elapse(const Duration(seconds: 10));
      clock.flushMicrotasks();
      expect(values, [3]);
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(values, [3, 4]);
      sub.cancel();
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      clock.flushMicrotasks();
      expect(calls, 4);
    });
  });
  test('permission denial does not retry or reveal stale data', () {
    fakeAsync((clock) {
      var calls = 0, closed = false;
      final errors = <Object>[];
      final sub = recoveringPoll<int>(
              active: () => true,
              fetch: () async {
                calls++;
                throw FirebaseException(
                    plugin: 'cloud_functions', code: 'permission-denied');
              })
          .listen((_) => fail('must not emit data'),
              onError: errors.add, onDone: () => closed = true);
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      clock.flushMicrotasks();
      expect(calls, 1);
      expect(errors.length, 1);
      expect(closed, isTrue);
      sub.cancel();
      clock.flushMicrotasks();
    });
  });
  test('session change discards an in-flight response', () {
    fakeAsync((clock) {
      var active = true;
      final pending = Completer<int>();
      final values = <int>[];
      final sub =
          recoveringPoll(active: () => active, fetch: () => pending.future)
              .listen(values.add);
      clock.flushMicrotasks();
      active = false;
      pending.complete(99);
      clock.flushMicrotasks();
      expect(values, isEmpty);
      sub.cancel();
      clock.flushMicrotasks();
    });
  });
  test('timeout retries reads and ignores late results', () {
    fakeAsync((clock) {
      final pending = Completer<int>();
      var calls = 0;
      final values = <int>[], errors = <Object>[];
      final sub = recoveringPoll(
          active: () => true,
          fetch: () {
            calls++;
            return calls == 1 ? pending.future : Future.value(2);
          }).listen(values.add, onError: errors.add);
      clock.elapse(const Duration(seconds: 20));
      clock.flushMicrotasks();
      expect(errors.single, isA<TimeoutException>());
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      pending.complete(1);
      clock.flushMicrotasks();
      expect(values, [2]);
      sub.cancel();
      clock.flushMicrotasks();
    });
  });
}
