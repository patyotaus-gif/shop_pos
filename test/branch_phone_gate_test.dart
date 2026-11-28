import 'package:shop_pos/widgets/merchant_phone_gate.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Token extends Fake implements IdTokenResult {
  _Token(this.authTime, this.phone);
  final String phone;
  @override
  final DateTime authTime;
  @override
  String get signInProvider => 'phone';
  @override
  String get token => 'local-only-phone-token';
  @override
  Map<String, dynamic> get claims => {'phone_number': phone};
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  String? phoneNumber;
  DateTime signedAt = DateTime.now();
  @override
  String get email => 'owner@example.test';
  @override
  String get displayName => 'ผู้ทดสอบ';
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async =>
      _Token(signedAt, phoneNumber!);
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  _User currentUser;
  @override
  Stream<User?> authStateChanges() => Stream.value(currentUser);
  int sends = 0;
  String? requestedNumber;
  PhoneVerificationCompleted? autoComplete;
  @override
  Future<void> setLanguageCode(String? languageCode) async {}
  @override
  Future<void> verifyPhoneNumber({
    String? phoneNumber,
    PhoneMultiFactorInfo? multiFactorInfo,
    required PhoneVerificationCompleted verificationCompleted,
    required PhoneVerificationFailed verificationFailed,
    required PhoneCodeSent codeSent,
    required PhoneCodeAutoRetrievalTimeout codeAutoRetrievalTimeout,
    String? autoRetrievedSmsCodeForTesting,
    Duration timeout = const Duration(seconds: 30),
    int? forceResendingToken,
    MultiFactorSession? multiFactorSession,
  }) async {
    sends++;
    requestedNumber = phoneNumber;
    autoComplete = verificationCompleted;
    codeSent('demo-verification', 7);
  }
  // A phone sign-in, identity link or other unexpected mutation on the primary
  // instance fails the test through Fake.noSuchMethod.
}

class _SignedPhone extends Fake implements UserCredential {
  _SignedPhone(this.user);
  @override
  final _User user;
}

class _PhoneAuth extends Fake implements FirebaseAuth {
  @override
  _User? currentUser;
  int signIns = 0, signOuts = 0;
  @override
  Future<void> signOut() async {
    currentUser = null;
    signOuts++;
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    if ((credential as PhoneAuthCredential).smsCode != '123456') {
      throw FirebaseAuthException(code: 'invalid-verification-code');
    }
    signIns++;
    return _SignedPhone(
        currentUser = _User('phone-only')..phoneNumber = '+66812345678');
  }
}

Future<void> _tap(WidgetTester t, String label) async {
  final f = find.text(label);
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(f, 160,
        scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await t.pumpAndSettle();
}


void main() {
  testWidgets('existing owner stays blocked until the server saves the OTP; later logins skip the prompt', (t) async {
    final primary = _Auth(_User('existing')), isolated = _PhoneAuth();
    var verified = false;
    var saves = 0;
    Widget app() => MaterialApp(home: MerchantPhoneGate(
      ownerId: 'existing', quickUnlock: false, auth: primary,
      readStatus: (id) async => verified ? 'verified' : 'required',
      phoneAuthFactory: (_, __) async => isolated,
      verify: (uid, token) async {
        expect(uid, 'existing');
        expect(token, 'local-only-phone-token');
        if (++saves == 1) throw FirebaseFunctionsException(code: 'unavailable', message: 'กรุณาลองอีกครั้ง');
        verified = true;
      },
      child: const Text('พื้นที่ร้านเดิม'),
    ));
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.text('ยืนยันเบอร์มือถือก่อนขอเพิ่มสาขา'), findsOneWidget);
    expect(find.text('พื้นที่ร้านเดิม'), findsNothing);
    expect(primary.sends, 0);
    await t.enterText(find.byType(TextField).first, '0812345678');
    await _tap(t, 'ส่งรหัส OTP');
    await t.enterText(find.byType(TextField).last, '000000');
    await _tap(t, 'ยืนยันรหัส');
    expect(saves, 0);
    await t.enterText(find.byType(TextField).last, '123456');
    await _tap(t, 'ยืนยันรหัส');
    expect(find.text('พื้นที่ร้านเดิม'), findsNothing);
    await _tap(t, 'ลองบันทึกการยืนยันอีกครั้ง');
    expect(find.text('พื้นที่ร้านเดิม'), findsOneWidget);
    expect(primary.sends, 1);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(find.text('พื้นที่ร้านเดิม'), findsOneWidget);
    expect(find.text('ส่งรหัส OTP'), findsNothing);
  });

  testWidgets('an unavailable phone status keeps the workspace closed until retry', (t) async {
    var attempts = 0;
    await t.pumpWidget(MaterialApp(home: MerchantPhoneGate(
      ownerId: 'shop', quickUnlock: false, auth: _Auth(_User('shop')),
      readStatus: (_) async {
        if (++attempts == 1) throw StateError('unavailable');
        return 'required';
      },
      child: const Text('พื้นที่ร้านเดิม'),
    )));
    await t.pumpAndSettle();
    expect(find.text('ยังตรวจสอบการยืนยันเบอร์ไม่ได้'), findsOneWidget);
    expect(find.text('พื้นที่ร้านเดิม'), findsNothing);
    await _tap(t, 'ลองอีกครั้ง');
    expect(find.text('ยืนยันเบอร์มือถือก่อนขอเพิ่มสาขา'), findsOneWidget);
    expect(find.text('พื้นที่ร้านเดิม'), findsNothing);
  });

}
