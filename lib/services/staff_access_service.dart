import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'auto_print_service.dart';

class StaffAccessService {
  static Future<Map<String, dynamic>> work(String action,
          [Map<String, dynamic> data = const {}]) =>
      call('staffWork',
          {'shopId': AuthService.shopId, 'action': action, ...data});

  static Future<Map<String, dynamic>> read(
          String collection, String id) async =>
      firestoreDates(
          (await work('read', {'collection': collection, 'id': id}))['record']
              as Map);

  static Stream<List<Map<String, dynamic>>> watch(String collection) async* {
    final uid = AuthService.currentUser?.uid;
    while (AuthService.isStaff && AuthService.currentUser?.uid == uid) {
      final result = await work('read', {'collection': collection});
      yield (result['records'] as List)
          .map((r) => firestoreDates(r as Map))
          .toList();
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  static Stream<Map<String, dynamic>> watchRecord(
      String collection, String id) async* {
    final uid = AuthService.currentUser?.uid;
    while (AuthService.isStaff && AuthService.currentUser?.uid == uid) {
      yield await read(collection, id);
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  static bool can(String permission) =>
      !AuthService.isStaff ||
      (_cacheUid == AuthService.currentUser?.uid &&
          (_cache?['permissions'] as Map?)?[permission] == true);
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
    dynamic convert(dynamic value, [String key = '']) {
      if (value is Map) {
        return value
            .map((k, v) => MapEntry(k.toString(), convert(v, k.toString())));
      }
      if (value is List) return value.map((v) => convert(v)).toList();
      if (value is String && key.endsWith('At')) {
        final date = DateTime.tryParse(value);
        if (date != null) return Timestamp.fromDate(date);
      }
      return value;
    }

    return Map<String, dynamic>.from(convert(raw) as Map);
  }

  static Future<void> switchTo(String id, String pin) async {
    final result =
        await call('staffSwitchSession', {'staffId': id, 'pin': pin});
    await AutoPrintService.stopLocal();
    _cache = null;
    await AuthService.rememberedOwner.clear();
    AuthService.ownerUnlocked = false;
    await FirebaseAuth.instance
        .signInWithCustomToken(result['token'] as String);
    unlocked.value = true;
  }
}
