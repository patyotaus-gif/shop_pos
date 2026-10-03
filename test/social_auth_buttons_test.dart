import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/social_auth_buttons.dart';
import 'package:shop_pos/services/social_auth_service.dart';

void main() {
  testWidgets('Google and Apple choices are visible on iOS', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
            body: SocialAuthButtons(authenticate: (_) async => false))));
    expect(find.text('ดำเนินการต่อด้วย Google'), findsOneWidget);
    expect(find.text('ดำเนินการต่อด้วย Apple'), findsOneWidget);
  });
  testWidgets(
      'both provider choices disable during authentication and cancel stays on screen',
      (tester) async {
    final result = Completer<bool>();
    var calls = 0, success = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SocialAuthButtons(
                authenticate: (p) {
                  calls++;
                  expect(p, SocialProvider.google);
                  return result.future;
                },
                onSuccess: () => success++))));
    await tester.tap(find.text('ดำเนินการต่อด้วย Google'));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'ดำเนินการต่อด้วย Apple'))
            .onPressed,
        isNull);
    result.complete(false);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(success, 0);
    expect(find.text('ดำเนินการต่อด้วย Google'), findsOneWidget);
  });
  testWidgets('linking requires explicit consent before opening provider',
      (tester) async {
    var called = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SocialAuthButtons(
                link: true,
                authenticate: (p) async {
                  called = true;
                  return true;
                }))));
    await tester.tap(find.text('เชื่อมบัญชี Apple'));
    await tester.pumpAndSettle();
    expect(called, false);
    await tester.tap(find.text('เชื่อมบัญชี').last);
    await tester.pumpAndSettle();
    expect(called, true);
    expect(find.text('เชื่อม Apple กับร้านเดิมแล้ว'), findsOneWidget);
  });
  testWidgets('provider error preserves sign-in choices', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SocialAuthButtons(authenticate: (p) async {
      throw StateError(SocialAuthService.messageFor(
          'account-exists-with-different-credential'));
    }))));
    await tester.tap(find.text('ดำเนินการต่อด้วย Apple'));
    await tester.pumpAndSettle();
    expect(find.textContaining('อีเมลนี้มีบัญชีเดิมแล้ว'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'ดำเนินการต่อด้วย Google'))
            .onPressed,
        isNotNull);
  });
}
