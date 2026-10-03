import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'auth_service.dart';

enum SocialProvider { google, apple }

extension SocialProviderName on SocialProvider {
  String get label => this == SocialProvider.google ? 'Google' : 'Apple';
  String get id => this == SocialProvider.google ? 'google.com' : 'apple.com';
}

class SocialAuthService {
  static Future<void>? _googleReady;
  static bool _busy = false;

  /// Linking always uses the authenticated owner UID. Never merge shops by email.
  /// Returns false for a dismissed account picker, otherwise propagates a safe error.
  static Future<bool> authenticate(SocialProvider provider,
      {bool link = false, bool remember = false}) async {
    if (_busy) return false;
    _busy = true;
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    final previousUnlock = AuthService.ownerUnlocked;
    try {
      if (link &&
          (user == null || AuthService.isStaff || !AuthService.ownerUnlocked)) {
        throw StateError('กรุณาเข้าสู่ระบบเจ้าของร้านก่อนเชื่อมบัญชี');
      }
      if (!link) {
        await AuthService.rememberedOwner.clear();
        AuthService.ownerUnlocked = true;
      }
      final AuthProvider oauth = provider == SocialProvider.google
          ? (GoogleAuthProvider()
            ..setCustomParameters({'prompt': 'select_account'}))
          : (AppleAuthProvider()
            ..addScope('email')
            ..addScope('name'));
      if (kIsWeb) {
        if (link) {
          await user!.linkWithPopup(oauth);
        } else {
          await auth.signInWithPopup(oauth);
        }
      } else if (provider == SocialProvider.apple) {
        if (link) {
          await user!.linkWithProvider(oauth);
        } else {
          await auth.signInWithProvider(oauth);
        }
      } else {
        _googleReady ??= GoogleSignIn.instance.initialize();
        await _googleReady;
        // Always show account selection, including when handing the till back to its owner.
        await GoogleSignIn.instance.signOut();
        final account = await GoogleSignIn.instance.authenticate();
        final credential = GoogleAuthProvider.credential(
            idToken: account.authentication.idToken);
        if (link) {
          await user!.linkWithCredential(credential);
        } else {
          await auth.signInWithCredential(credential);
        }
      }
      if (link && auth.currentUser?.uid != user!.uid) {
        throw StateError('บัญชีเปลี่ยนระหว่างเชื่อม กรุณาเข้าสู่ระบบใหม่');
      }
      await AuthService.refreshFounderClaim();
      if (!link && remember && !auth.currentUser!.uid.startsWith('staff_')) {
        await AuthService.rememberedOwner.save(auth.currentUser!.uid);
      }
      return true;
    } on GoogleSignInException catch (e) {
      AuthService.ownerUnlocked = previousUnlock;
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw StateError('เข้า Google ไม่สำเร็จ กรุณาลองใหม่หรือใช้อีเมล');
    } on FirebaseAuthException catch (e) {
      AuthService.ownerUnlocked = previousUnlock;
      if ([
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-cancelled',
        'canceled'
      ].contains(e.code)) {
        return false;
      }
      throw StateError(messageFor(e.code));
    } catch (_) {
      AuthService.ownerUnlocked = previousUnlock;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  static String messageFor(String code) => switch (code) {
        'account-exists-with-different-credential' =>
          'อีเมลนี้มีบัญชีเดิมแล้ว กรุณาเข้าด้วยวิธีเดิม แล้วไปที่ ตั้งค่า → เชื่อมบัญชี เพื่อใช้ร้านเดิม',
        'credential-already-in-use' ||
        'email-already-in-use' =>
          'บัญชีนี้เชื่อมกับผู้ใช้อื่นแล้ว กรุณาใช้บัญชีเดิม ระบบจะไม่รวมร้านให้อัตโนมัติ',
        'provider-already-linked' => 'บัญชีนี้เชื่อมไว้แล้ว',
        'requires-recent-login' => 'กรุณาเข้าสู่ระบบใหม่ก่อนเชื่อมบัญชี',
        'operation-not-allowed' ||
        'configuration-not-found' =>
          'ช่องทางนี้ยังไม่พร้อมใช้งาน กรุณาเข้าสู่ระบบด้วยอีเมล',
        'network-request-failed' =>
          'เชื่อมต่อไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองใหม่',
        'user-disabled' => 'บัญชีนี้ถูกระงับการใช้งาน',
        _ => 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่หรือใช้วิธีเดิม',
      };
}
