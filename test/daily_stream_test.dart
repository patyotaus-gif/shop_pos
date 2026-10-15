import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/utils/daily_stream.dart';

void main() {
  test('open daily report switches query at midnight and year boundary',
      () async {
    var now = DateTime(2026, 12, 31, 23, 59, 59, 980);
    final queried = <DateTime>[];
    final values = <int>[];
    final sources = <StreamController<int>>[];
    final firstValue = Completer<void>();
    final newDay = Completer<void>();
    final newValue = Completer<void>();
    final subscription = watchDaily<int>((day) {
      queried.add(day);
      final source = StreamController<int>.broadcast();
      sources.add(source);
      if (sources.length == 2) newDay.complete();
      return source.stream;
    }, now: () => now).listen((value) {
      values.add(value);
      if (value == 70) firstValue.complete();
      if (value == 0) newValue.complete();
    });
    try {
      sources.first.add(70);
      now = DateTime(2027, 1, 1);
      await firstValue.future.timeout(const Duration(seconds: 2));
      await newDay.future.timeout(const Duration(seconds: 2));
      expect(queried, [DateTime(2026, 12, 31), DateTime(2027, 1, 1)]);
      expect(sources.first.hasListener, isFalse);
      sources.first.add(999);
      sources.last.add(0);
      await newValue.future.timeout(const Duration(seconds: 2));
      expect(values, [70, 0]);
    } finally {
      await subscription.cancel();
      expect(sources.last.hasListener, isFalse);
      for (final source in sources) {
        await source.close();
      }
    }
  });

  test('delayed timer uses actual day and query errors remain visible',
      () async {
    var now = DateTime(2026, 10, 15, 23, 59, 59, 980);
    final received = Completer<DateTime>();
    final errors = <Object>[];
    final subscription = watchDaily<DateTime>((day) {
      if (day.day == 15) throw StateError('connection unavailable');
      return Stream.value(day);
    }, now: () => now).listen(received.complete, onError: errors.add);
    try {
      now = DateTime(2026, 10, 18, 10);
      final day = await received.future.timeout(const Duration(seconds: 2));
      expect(day, DateTime(2026, 10, 18));
      expect(errors.single, isA<StateError>());
    } finally {
      await subscription.cancel();
    }
  });
}
