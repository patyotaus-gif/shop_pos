import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/notification_registration.dart';

void main() {
  test(
      'snapshot rebuilds and duplicate refreshes do not write token repeatedly',
      () async {
    final registration = NotificationRegistration();
    final refresh = StreamController<String>.broadcast();
    addTearDown(refresh.close);
    addTearDown(registration.stop);
    var writes = 0, requests = 0;
    late Future<void> Function() start;
    start = () => registration.start('shop',
        getToken: () async {
          requests++;
          return 'token';
        },
        tokenChanges: refresh.stream,
        save: (_, token) async {
          writes++;
          // Firestore metadata changes trigger the subscription gate again.
          unawaited(start());
        });
    await Future.wait(List.generate(20, (_) => start()));
    refresh.add('token');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    expect(writes, 1);
    refresh.add('new-token');
    await Future<void>.delayed(Duration.zero);
    expect(writes, 2);
  });
  test(
      'switching accounts cancels old refresh listeners and ignores stale token fetch',
      () async {
    final registration = NotificationRegistration();
    final refresh = StreamController<String>.broadcast();
    addTearDown(refresh.close);
    addTearDown(registration.stop);
    final oldToken = Completer<String?>();
    final writes = <String>[];
    Future<void> save(String shop, String token) async =>
        writes.add('$shop:$token');
    final first = registration.start('old',
        getToken: () => oldToken.future,
        tokenChanges: refresh.stream,
        save: save);
    await registration.start('new',
        getToken: () async => 'new-token',
        tokenChanges: refresh.stream,
        save: save);
    oldToken.complete('old-token');
    await first;
    refresh.add('refreshed');
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['new:new-token', 'new:refreshed']);
    registration.stop();
    refresh.add('signed-out');
    await Future<void>.delayed(Duration.zero);
    expect(writes.length, 2);
  });
  test('failed registration does not retry on every rebuild', () async {
    final registration = NotificationRegistration();
    addTearDown(registration.stop);
    var writes = 0;
    for (var i = 0; i < 5; i++) {
      await registration.start('shop',
          getToken: () async => 'token',
          tokenChanges: const Stream.empty(),
          save: (_, token) async {
            writes++;
            throw StateError('offline');
          });
    }
    expect(writes, 1);
  });
}
