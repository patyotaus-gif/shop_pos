import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/screens/verify_email_screen.dart';

class _Token extends Fake implements IdTokenResult {
  _Token(this.claims);
  @override
  final Map<String, dynamic> claims;
}

class _User extends Fake implements User {
  @override
  final uid = 'merchant-1';
  @override
  final String email = 'merchant@example.test';
  @override
  bool emailVerified = false;
  bool tookAction = false;
  bool failSend = false;
  int sends = 0;
  int refreshes = 0;
  Map<String, dynamic> extraClaims = {};
  @override
  List<UserInfo> providerData = [];
  @override
  Future<void> reload() async {
    emailVerified = tookAction;
  }

  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (forceRefresh) refreshes++;
    return _Token({'email_verified': emailVerified, ...extraClaims});
  }

  @override
  Future<void> sendEmailVerification(
      [ActionCodeSettings? actionCodeSettings]) async {
    if (failSend) throw FirebaseAuthException(code: 'network-request-failed');
    sends++;
  }
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  final User currentUser;
  String? language;
  @override
  Future<void> setLanguageCode(String? languageCode) async {
    language = languageCode;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'launch sends one email, restart keeps cooldown and resume refreshes verified token',
      (tester) async {
    final user = _User();
    final auth = _Auth(user);
    final screen = MaterialApp(home: VerifyEmailScreen(user: user, auth: auth));
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    expect(find.text(user.email), findsOneWidget);
    expect(auth.language, 'th');
    expect(user.sends, 1);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen);
    await tester.pumpAndSettle();
    expect(user.sends, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    user.tookAction = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(user.refreshes, 1);
    expect(user.sends, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'failure offers retry, and an account verified elsewhere never gets an email',
      (tester) async {
    final user = _User()..failSend = true;
    await tester.pumpWidget(
        MaterialApp(home: VerifyEmailScreen(user: user, auth: _Auth(user))));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('ติดต่อระบบยืนยันอีเมลไม่สำเร็จ'), findsOneWidget);
    expect(user.sends, 0);
    user.failSend = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(user.sends, 1,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' / '));
    await tester.pumpWidget(const SizedBox());
    final verified = _User()..tookAction = true;
    await tester.pumpWidget(MaterialApp(
        home: VerifyEmailScreen(user: verified, auth: _Auth(verified))));
    await tester.pumpAndSettle();
    expect(verified.refreshes, 1);
    expect(verified.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'old owner PIN with uncertain provider asks for owner sign-in without sending email',
      (tester) async {
    final user = _User()
      ..extraClaims = {
        'ownerQuickUnlock': true,
        'firebase': {'sign_in_provider': 'custom'}
      };
    await tester.pumpWidget(
        MaterialApp(home: VerifyEmailScreen(user: user, auth: _Auth(user))));
    await tester.pumpAndSettle();
    expect(find.text('กลับไปเข้าสู่ระบบ'), findsOneWidget);
    expect(find.text('ส่งอีเมลยืนยันอีกครั้ง'), findsNothing);
    expect(user.sends, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
