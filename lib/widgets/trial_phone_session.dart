import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

typedef TrialPhoneAuthFactory = Future<FirebaseAuth> Function(
    FirebaseAuth primary, String ownerUid);
typedef TrialPhoneProof = ({
  String number,
  String token,
  DateTime authenticatedAt
});

Future<FirebaseAuth> ownerScopedTrialAuth(
    FirebaseAuth primary, String ownerUid) async {
  if (primary.currentUser?.uid != ownerUid) {
    throw FirebaseAuthException(code: 'user-mismatch');
  }
  // Distinct SDK storage prevents SMS sign-in from replacing the merchant, including after app restart.
  final identity = jsonEncode([primary.app.name, primary.tenantId, ownerUid]);
  final scope = base64Url.encode(utf8.encode(identity)).replaceAll('=', '');
  final name = 'pokpok-trial-phone-$scope';
  FirebaseApp app;
  try {
    app = Firebase.app(name);
  } on FirebaseException catch (e) {
    if (e.code != 'no-app') rethrow;
    try {
      app = await Firebase.initializeApp(
          name: name, options: primary.app.options);
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') rethrow;
      app = Firebase.app(name);
    }
  }
  if (primary.currentUser?.uid != ownerUid) {
    throw FirebaseAuthException(code: 'user-mismatch');
  }
  final isolated = FirebaseAuth.instanceFor(app: app);
  if (isolated.tenantId != primary.tenantId) {
    isolated.tenantId = primary.tenantId;
  }
  return isolated;
}

bool freshTrialPhoneProof(TrialPhoneProof proof) {
  final age = DateTime.now().difference(proof.authenticatedAt);
  return age >= const Duration(minutes: -2) &&
      age < const Duration(minutes: 30);
}

Future<TrialPhoneProof?> currentTrialPhoneProof(
    FirebaseAuth isolated, String ownerUid) async {
  final phoneUser = isolated.currentUser;
  final number = phoneUser?.phoneNumber;
  if (phoneUser == null || phoneUser.uid == ownerUid || number == null) {
    return null;
  }
  final result = await phoneUser.getIdTokenResult();
  final token = result.token, timestamp = result.authTime;
  if (isolated.currentUser?.uid != phoneUser.uid ||
      result.signInProvider != 'phone' ||
      result.claims?['phone_number'] != number ||
      token == null ||
      token.isEmpty ||
      timestamp == null) {
    return null;
  }
  final proof = (number: number, token: token, authenticatedAt: timestamp);
  return freshTrialPhoneProof(proof) ? proof : null;
}
