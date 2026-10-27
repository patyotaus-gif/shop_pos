import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_service.dart';
import 'auto_print_service.dart';
import 'notification_service.dart';
import 'staff_access_service.dart';

/// Only a random device binding is stored locally, never the owner's PIN,
/// password, refresh token or a reusable owner custom token.
class OwnerUnlockService {
  static const _storage = FlutterSecureStorage();
  static const _key = 'owner_unlock_device_v1';
  static bool get supported => !kIsWeb;

  static Future<Map<String, dynamic>?> _binding() async {
    if (!supported) return null;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (value['uid'] != AuthService.shopId) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> available() async => await _binding() != null;
  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
            bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  static Future<void> setup(String pin) async {
    if (!supported || AuthService.isStaff || !AuthService.ownerUnlocked) {
      throw StateError('กรุณาเข้าสู่ระบบเจ้าของร้านบนแอพก่อนตั้ง PIN');
    }
    final uid = AuthService.currentUser!.uid;
    final previous = await _binding();
    final binding = <String, dynamic>{
      'uid': uid,
      'deviceId': previous?['deviceId'] ?? _randomHex(16),
      'secret': _randomHex(32),
    };
    // Persist before enrollment, so a storage failure never enables a binding
    // that this device cannot subsequently access or disable.
    await _storage.write(key: _key, value: jsonEncode(binding));
    try {
      await StaffAccessService.call('setupOwnerUnlock', {
        'deviceId': binding['deviceId'],
        'secret': binding['secret'],
        'pin': pin,
      });
    } on FirebaseFunctionsException catch (e) {
      if ([
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'unauthenticated',
        'not-found'
      ].contains(e.code)) {
        if (previous == null) {
          await forget();
        } else {
          await _storage.write(key: _key, value: jsonEncode(previous));
        }
      }
      rethrow;
    }
    // PIN should be required on reopen even if personal-device remember was on.
    await AuthService.rememberedOwner.clear();
  }

  static Future<void> unlock(String pin) async {
    final binding = await _binding();
    if (binding == null) throw StateError('ไม่พบ PIN เจ้าของบนเครื่องนี้');
    final result = await StaffAccessService.call('unlockOwner', {
      'deviceId': binding['deviceId'],
      'secret': binding['secret'],
      'pin': pin,
    });
    await AutoPrintService.stopLocal();
    NotificationService.stopFCM();
    await AuthService.rememberedOwner.clear();
    StaffAccessService.unlocked.value = false;
    AuthService.ownerUnlocked = true;
    try {
      await FirebaseAuth.instance
          .signInWithCustomToken(result['token'] as String);
    } catch (_) {
      AuthService.ownerUnlocked = false;
      rethrow;
    }
  }

  static Future<void> disable() async {
    final binding = await _binding();
    if (binding != null) {
      await StaffAccessService.call('disableOwnerUnlock', {
        'deviceId': binding['deviceId'],
      });
    }
    await forget();
  }

  static Future<void> forget() => _storage.delete(key: _key);
}
