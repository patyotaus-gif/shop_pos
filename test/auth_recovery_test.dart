import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/auth_service.dart';
import 'package:shop_pos/widgets/recoverable_auth_builder.dart';

Widget gate(Stream<String?> Function() source) => MaterialApp(
      home: RecoverableAuthBuilder<String?>(
        streamFactory: source,
        builder: (context, snapshot, retry) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Text('checking');
          }
          if (snapshot.hasError) {
            return TextButton(onPressed: retry, child: const Text('retry'));
          }
          return Text(snapshot.data ?? 'login');
        },
      ),
    );

void main() {
  testWidgets('failed check stays locked and explicit retry restores session',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(gate(() => ++calls == 1
        ? Stream.error(FirebaseAuthException(code: 'network-request-failed'))
        : Stream.value('cashier')));
    await tester.pumpAndSettle();
    expect(find.text('cashier'), findsNothing);
    expect(find.text('login'), findsNothing);
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    expect(find.text('cashier'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('resume retries a failed check but not a healthy session',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(gate(() => ++calls == 1
        ? Stream.error(TimeoutException('connection'))
        : Stream.value('owner-locked')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('owner-locked'), findsOneWidget);
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('repeated failures do not loop or display protected content',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(gate(() {
      calls++;
      return Stream.error(StateError('missing staff claim'));
    }));
    await tester.pumpAndSettle();
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    expect(find.text('retry'), findsOneWidget);
    expect(find.text('login'), findsNothing);
  });

  testWidgets('sign-out event still reaches login after a stream error',
      (tester) async {
    final events = StreamController<String?>();
    await tester.pumpWidget(gate(() => events.stream));
    events.addError(StateError('check failed'));
    await tester.pumpAndSettle();
    events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    await events.close();
  });

  test('network failure does not tell the user their session expired', () {
    final message = AuthService.sessionErrorMessage(
        FirebaseAuthException(code: 'network-request-failed'));
    expect(message, contains('อินเทอร์เน็ต'));
    expect(message, isNot(contains('ออกจากระบบ')));
    expect(
        AuthService.sessionErrorMessage(
            FirebaseAuthException(code: 'user-token-expired')),
        contains('เข้าสู่ระบบใหม่'));
  });
}
