import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';
import 'remembered_owner.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final rememberedOwner = RememberedOwner();
  // Shared devices remain locked; personal devices can explicitly opt in.
  static bool ownerUnlocked = false;

  static String? _claimUid;
  static Map<String, dynamic> _claims = {};
  static bool get isStaff =>
      _claimUid != null &&
      _claimUid == currentUser?.uid &&
      _claims['staffRole'] == 'cashier';
  static String? get staffId => isStaff ? _claims['staffId'] as String? : null;
  static final Stream<User?> authStateStream =
      _auth.idTokenChanges().asyncMap((user) async {
    if (_claimUid != user?.uid) NotificationService.stopFCM();
    if (user != null) {
      final token = await user.getIdTokenResult();
      final claims = Map<String, dynamic>.from(token.claims ?? {});
      if (user.uid.startsWith('staff_') && claims['staffRole'] != 'cashier') {
        throw StateError('ไม่พบสิทธิ์พนักงาน กรุณาเข้าสู่ระบบใหม่');
      }
      _claims = claims;
      _claimUid = user.uid;
      _founderClaim = _claims['founder'] == true;
      if (isStaff) {
        ownerUnlocked = false;
      } else if (!ownerUnlocked) {
        ownerUnlocked = await rememberedOwner.matches(user.uid, isStaff: false);
      }
    } else {
      _founderClaim = false;
      _claims = {};
      _claimUid = null;
      ownerUnlocked = false;
    }
    return user;
  });

  static User? get currentUser => _auth.currentUser;

  /// shopId = Firebase Auth UID — ใช้เป็น key หลักใน Firestore
  static String? get shopId =>
      isStaff ? _claims['staffShopId'] as String? : _auth.currentUser?.uid;

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
    if (isStaff) return false;
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
    ownerUnlocked = true;
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      ownerUnlocked = false;
      return switch (e.code) {
        'email-already-in-use' => 'อีเมลนี้ถูกใช้งานแล้ว',
        'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        'weak-password' => 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร',
        _ => 'เกิดข้อผิดพลาด: ${e.message}',
      };
    }
  }

  static Future<String?> signIn(String email, String password,
      {bool remember = false}) async {
    try {
      await rememberedOwner.clear();
      ownerUnlocked = true;
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      await refreshFounderClaim();
      if (remember) {
        await rememberedOwner.save(_auth.currentUser!.uid);
      }
      return null;
    } on FirebaseAuthException catch (e) {
      ownerUnlocked = false;
      return switch (e.code) {
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
        'invalid-email' => 'รูปแบบอีเมลไม่ถูกต้อง',
        'user-disabled' => 'บัญชีนี้ถูกระงับการใช้งาน',
        'too-many-requests' => 'ลองใหม่อีกครั้งในภายหลัง',
        _ => 'เกิดข้อผิดพลาด: ${e.message}',
      };
    } catch (_) {
      return 'ไม่สามารถบันทึกการเข้าใช้งานบนเครื่องนี้ได้ กรุณาลองใหม่';
    }
  }

  static Future<void> signOut() async {
    NotificationService.stopFCM();
    ownerUnlocked = false;
    _founderClaim = false;
    try {
      await rememberedOwner.clear();
    } finally {
      await _auth.signOut();
    }
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
