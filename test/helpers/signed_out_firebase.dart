import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local Core/Auth only. Tests supply their own fake Firestore or table data.
void setupSignedOutFirebase() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  final originalAuth = FirebaseAuthPlatform.instance;
  FirebaseAuthPlatform.instance = _SignedOutAuth();
  setUpAll(() async => Firebase.initializeApp());
  tearDownAll(() => FirebaseAuthPlatform.instance = originalAuth);
}

class _SignedOutAuth extends FirebaseAuthPlatform {
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({
    PigeonUserDetails? currentUser,
    String? languageCode,
  }) =>
      this;

  @override
  UserPlatform? get currentUser => null;
}
