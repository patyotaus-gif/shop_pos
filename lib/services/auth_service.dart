import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get authStateStream => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  /// shopId = Firebase Auth UID — ใช้เป็น key หลักใน Firestore
  static String? get shopId => _auth.currentUser?.uid;

  /// Bootstrap founder allowlist — mirrors FOUNDER_EMAILS in
  /// functions/index.js. Additional founders are granted the `founder` custom
  /// claim (see [refreshFounderClaim]); this list just keeps the original
  /// founder working without waiting on a token refresh. Either way the
  /// security boundary is server-side — this only shows/hides UI.
  static const _founderEmails = {'patyotaus@gmail.com'};

  /// Cached `founder` custom claim from the current user's ID token, refreshed
  /// by [refreshFounderClaim] on sign-in / startup.
  static bool _founderClaim = false;

  static bool get isFounder {
    final email = _auth.currentUser?.email?.toLowerCase();
    return _founderClaim || (email != null && _founderEmails.contains(email));
  }

  /// Re-reads the `founder` custom claim from the current user's ID token and
  /// caches it. Call after sign-in and at startup. Pass [forceRefresh] right
  /// after a claim change to bypass the ~1h token cache.
  static Future<void> refreshFounderClaim({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      _founderClaim = false;
      return;
    }
    try {
      final res = await user.getIdTokenResult(forceRefresh);
      _founderClaim = res.claims?['founder'] == true;
    } catch (_) {
      // Keep the cached value; the email fallback still covers the bootstrap
      // founder if the token fetch fails.
    }
  }

  static Future<String?> register(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'email-already-in-use' => 'อีเมลนี้ถูกใช้งานแล้ว',
        'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        'weak-password' => 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร',
        _ => 'เกิดข้อผิดพลาด: ${e.message}',
      };
    }
  }

  static Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      await refreshFounderClaim();
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
        'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        'user-disabled' => 'บัญชีนี้ถูกระงับการใช้งาน',
        'too-many-requests' => 'ลองใหม่อีกครั้งในภายหลัง',
        _ => 'เกิดข้อผิดพลาด: ${e.message}',
      };
    }
  }

  static Future<void> signOut() {
    _founderClaim = false;
    return _auth.signOut();
  }

  static Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'user-not-found' => 'ไม่พบบัญชีที่ใช้อีเมลนี้',
        'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        _ => 'เกิดข้อผิดพลาด: ${e.message}',
      };
    }
  }
}
