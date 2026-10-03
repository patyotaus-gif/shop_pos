import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';

class StaffAccessService {
  static final unlocked = ValueNotifier(false);
  static Map<String, dynamic>? _cache;
  static String? _cacheUid;
  static DateTime? _cachedAt;
  static Future<Map<String, dynamic>> call(String name,
      [Map<String, dynamic> data = const {}]) async {
    final result =
        await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable(name)
            .call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<Map<String, dynamic>> workspace() async {
    final uid = AuthService.currentUser?.uid;
    if (_cache != null &&
        _cacheUid == uid &&
        DateTime.now().difference(_cachedAt!).inSeconds < 10) {
      return _cache!;
    }
    final result = await call('staffWorkspace');
    _cache = result;
    _cacheUid = uid;
    _cachedAt = DateTime.now();
    return result;
  }

  static Stream<Map<String, dynamic>> watchWorkspace() async* {
    while (AuthService.isStaff) {
      yield await workspace();
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  static Map<String, dynamic> firestoreDates(Map raw) {
    final data = Map<String, dynamic>.from(raw);
    for (final field in ['createdAt', 'trialEndsAt', 'subscriptionEndsAt']) {
      if (data[field] is String) {
        data[field] = Timestamp.fromDate(DateTime.parse(data[field]));
      }
    }
    return data;
  }

  static Future<void> switchTo(String id, String pin) async {
    final result =
        await call('staffSwitchSession', {'staffId': id, 'pin': pin});
    _cache = null;
    await AuthService.rememberedOwner.clear();
    AuthService.ownerUnlocked = false;
    await FirebaseAuth.instance
        .signInWithCustomToken(result['token'] as String);
    unlocked.value = true;
  }
}
