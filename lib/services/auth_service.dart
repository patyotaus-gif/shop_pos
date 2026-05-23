import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get authStateStream => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  /// shopId = Firebase Auth UID — ใช้เป็น key หลักใน Firestore
  static String? get shopId => _auth.currentUser?.uid;

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

  static Future<void> signOut() => _auth.signOut();

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
