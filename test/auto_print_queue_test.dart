import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/auto_print_queue.dart';

void main() {
  const job = {'jobId': 'one', 'attempt': 'attempt-one', 'kind': 'receipt'};
  test('lost result acknowledgement retries finish only, never physical output',
      () async {
    var prints = 0, finishes = 0, claims = 0;
    final queue = AutoPrintQueue(
        active: () => true,
        status: (_) async {},
        send: (_) async {
          prints++;
        },
        call: (method, data) async {
          if (method == 'claimAutoPrint') {
            return claims++ == 0 ? job : {'empty': true};
          }
          expect(data['outcome'], 'sent');
          if (++finishes == 1) throw StateError('reply lost');
          return {'success': true};
        });
    await expectLater(queue.pump(), throwsStateError);
    await queue.pump();
    expect(prints, 1);
    expect(finishes, 2);
    expect(claims, 2);
  });
  test('overlapping wakeups serialize one print and claim', () async {
    final released = Completer<void>();
    var claims = 0, prints = 0;
    final queue = AutoPrintQueue(
        active: () => true,
        status: (_) async {},
        send: (_) async {
          prints++;
          await released.future;
        },
        call: (method, _) async {
          if (method == 'claimAutoPrint') {
            return claims++ == 0 ? job : {'empty': true};
          }
          return {'success': true};
        });
    final first = queue.pump();
    await Future<void>.delayed(Duration.zero);
    await queue.pump();
    expect(prints, 1);
    expect(claims, 1);
    released.complete();
    await first;
  });
  test(
      'partial output stops at review instead of retrying or printing next job',
      () async {
    var prints = 0, claims = 0;
    final queue = AutoPrintQueue(
        active: () => true,
        status: (_) async {},
        send: (_) async {
          prints++;
          throw StateError('partial');
        },
        call: (method, data) async {
          if (method == 'claimAutoPrint') {
            return claims++ == 0 ? job : {'blocked': 'one'};
          }
          expect(data['outcome'], 'needsReview');
          return {'success': true};
        });
    await queue.pump();
    await queue.pump();
    expect(prints, 1);
  });
  test('stop during claim prevents output; durable claim remains for review',
      () async {
    var active = true, prints = 0;
    final queue = AutoPrintQueue(
        active: () => active,
        status: (_) async {},
        send: (_) async {
          prints++;
        },
        call: (method, data) async {
          active = false;
          return job;
        });
    await queue.pump();
    expect(prints, 0);
  });
  test('claim failure never sends output and can recover on next wakeup',
      () async {
    var calls = 0, prints = 0;
    final queue = AutoPrintQueue(
        active: () => true,
        status: (_) async {},
        send: (_) async {
          prints++;
        },
        call: (method, data) async {
          if (calls++ == 0) throw StateError('network');
          return {'empty': true};
        });
    await expectLater(queue.pump(), throwsStateError);
    await queue.pump();
    expect(prints, 0);
  });
}
