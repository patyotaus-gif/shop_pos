import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import 'auth_service.dart';
import 'offline_store.dart';
import 'staff_access_service.dart';

class OfflineService {
  static const _secrets = FlutterSecureStorage();
  static Future<OfflineStore>? _store;
  static final changes = ValueNotifier(0);
  static String? _unlocked;
  static bool _syncing = false;
  static Timer? _timer;
  static Future<OfflineStore> get store => _store ??= _open();
  @visibleForTesting
  static void useTestStore(OfflineStore? value) {
    _timer?.cancel();
    _timer = null;
    _unlocked = null;
    _store = value == null ? null : Future.value(value);
  }

  static Future<OfflineStore> _open() async => OfflineStore(await openDatabase(
      '${await getDatabasesPath()}/offline_cash.db',
      version: 1,
      onCreate: OfflineStore.create));
  static void start() {
    _timer ??=
        Timer.periodic(const Duration(seconds: 30), (_) => unawaited(sync()));
  }

  static Future<String> _hash(String pin, List<int> salt) async =>
      base64Encode(await (await Pbkdf2(
                  macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256)
              .deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt))
          .extractBytes());
  static Future<List<Map<String, Object?>>> profiles() async =>
      (await store).permits();
  static Future<int> pendingForShop(String shopId) async {
    final local = await store;
    final ids = (await local.permits())
        .where((p) => p['shop'] == shopId)
        .map((p) => p['id'])
        .toSet();
    return (await local.receipts())
        .where((r) => ids.contains(r['permit']) && r['status'] != 'synced')
        .length;
  }

  static Future<Map<String, dynamic>> prepare(String pin) async {
    if (!RegExp(r'^\d{6,8}$').hasMatch(pin)) {
      throw StateError('ใช้ PIN ออฟไลน์ 6–8 หลัก');
    }
    if (!(AuthService.isStaff
        ? StaffAccessService.unlocked.value
        : AuthService.ownerUnlocked)) {
      throw StateError('กรุณาเข้าสู่ระบบก่อนเตรียมออฟไลน์');
    }
    final local = await store;
    final profiles = await local.permits(), rows = await local.receipts();
    final ids = profiles
        .where((p) => p['shop'] == AuthService.shopId)
        .map((p) => p['id'])
        .toSet();
    if (rows.any((r) => ids.contains(r['permit']) && r['status'] != 'synced')) {
      throw StateError('ซิงก์บิลค้างของร้านนี้ให้ครบก่อนเตรียมข้อมูลใหม่');
    }
    final p = await StaffAccessService.call('offlinePrepare');
    final salt = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final secret = p.remove('secret');
    await _secrets.write(
        key: 'offline-${p['id']}',
        value: jsonEncode({
          'secret': secret,
          'salt': salt,
          'hash': await _hash(pin, salt),
          'attempts': 0,
          'lockedUntil': 0,
          'lastSeen': DateTime.now().millisecondsSinceEpoch
        }));
    await local.savePermit(p);
    _unlocked = p['id'] as String;
    changes.value++;
    return p;
  }

  static Future<Map<String, dynamic>> unlock(
      Map<String, Object?> profile, String pin) async {
    final p = Map<String, dynamic>.from(jsonDecode(profile['data'] as String));
    final raw = await _secrets.read(key: 'offline-${p['id']}');
    if (raw == null) {
      throw StateError('ไม่พบสิทธิ์ในเครื่อง กรุณาเตรียมใหม่ขณะออนไลน์');
    }
    final secret = Map<String, dynamic>.from(jsonDecode(raw));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now < (secret['lockedUntil'] as int)) {
      throw StateError('PIN ผิดหลายครั้ง กรุณารอ 5 นาที');
    }
    if (await _hash(pin, List<int>.from(secret['salt'])) != secret['hash']) {
      final attempts = (secret['attempts'] as int) + 1;
      secret['attempts'] = attempts >= 5 ? 0 : attempts;
      if (attempts >= 5) secret['lockedUntil'] = now + 300000;
      await _secrets.write(
          key: 'offline-${p['id']}', value: jsonEncode(secret));
      throw StateError('PIN ออฟไลน์ไม่ถูกต้อง');
    }
    secret['attempts'] = 0;
    await _secrets.write(key: 'offline-${p['id']}', value: jsonEncode(secret));
    _unlocked = p['id'] as String;
    return p;
  }

  static void lock() => _unlocked = null;
  // Match priceCart: floor unit prices at zero and round each line to satang.
  static double lineTotal(CartItem item) =>
      (max(0, item.unitPrice) * item.quantity * 100).round() / 100;
  static double cartTotal(List<CartItem> cart) =>
      (cart.fold<double>(0, (sum, item) => sum + lineTotal(item)) * 100)
          .round() /
      100;
  static Future<Map<String, dynamic>> checkout(
      Map<String, dynamic> p, List<CartItem> cart, double paid) async {
    if (_unlocked != p['id']) throw StateError('กรุณาปลดล็อกออฟไลน์');
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getKeys().any((key) =>
        key.startsWith('pending-checkout-${p['shopId']}') &&
        prefs.getString(key) != null)) {
      throw StateError(
          'มีบิลออนไลน์รอยืนยัน กรุณาตรวจบิลเดิมก่อนรับเงินบิลใหม่');
    }
    final raw = await _secrets.read(key: 'offline-${p['id']}');
    if (raw == null) throw StateError('ไม่พบสิทธิ์ออฟไลน์');
    final secret = Map<String, dynamic>.from(jsonDecode(raw));
    final now = DateTime.now();
    if (now.isAfter(DateTime.parse(p['expiresAt'])) ||
        now.isBefore(DateTime.parse(p['issuedAt'])
            .subtract(const Duration(minutes: 1))) ||
        now.millisecondsSinceEpoch < (secret['lastSeen'] as int) - 60000) {
      throw StateError(
          'สิทธิ์ออฟไลน์หมดอายุหรือเวลาเครื่องเปลี่ยน กรุณาเชื่อมต่ออินเทอร์เน็ต');
    }
    if (cart.isEmpty ||
        cart.length > 50 ||
        cart.any((i) => i.quantity < 1 || i.quantity > 99 || i.discount != 0)) {
      throw StateError('ตรวจรายการสินค้า (สูงสุด 50 รายการ รายการละ 99 ชิ้น)');
    }
    final total = cartTotal(cart);
    if (!paid.isFinite ||
        paid < total ||
        paid > 1e9 ||
        !total.isFinite ||
        total < 0) {
      throw StateError('จำนวนเงินรับไม่ถูกต้อง');
    }
    secret['lastSeen'] = now.millisecondsSinceEpoch;
    await _secrets.write(key: 'offline-${p['id']}', value: jsonEncode(secret));
    final bill = <String, dynamic>{
      'id': const Uuid().v4(),
      'permitId': p['id'],
      'createdAt': now.toUtc().toIso8601String(),
      'total': total,
      'paid': paid,
      'discount': 0,
      'paymentMethod': 'cash',
      'items': cart
          .map((i) => {
                'productId': i.product.id,
                'quantity': i.quantity,
                'optionIds': i.modifiers.map((m) => m.optionId).toList(),
                'notes': i.notes
              })
          .toList(),
      'displayItems': cart
          .map((i) => {
                'name': i.product.name,
                'quantity': i.quantity,
                'subtotal': lineTotal(i),
                'options': i.modifiers.map((m) => m.optionName).join(', ')
              })
          .toList()
    };
    await (await store).enqueue(p, bill);
    changes.value++;
    unawaited(sync());
    return bill;
  }

  static Future<void> sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      if (AuthService.currentUser == null) return;
      final local = await store, profiles = await local.permits();
      for (final p in profiles) {
        if (p['shop'] != AuthService.shopId ||
            (AuthService.isStaff && p['uid'] != AuthService.currentUser!.uid)) {
          continue;
        }
        final raw = await _secrets.read(key: 'offline-${p['id']}');
        if (raw == null) continue;
        final secret = jsonDecode(raw)['secret'];
        for (final row in await local.receipts(permit: p['id'] as String)) {
          if (row['status'] != 'pending') continue;
          try {
            final result = await StaffAccessService.call('offlineSync', {
              ...Map<String, dynamic>.from(
                  jsonDecode(row['payload'] as String)),
              'secret': secret
            });
            await local.result(row['id'] as String, 'synced',
                (result['review'] as List).join(' · '));
          } on FirebaseFunctionsException catch (e) {
            if (['invalid-argument', 'already-exists', 'failed-precondition']
                .contains(e.code)) {
              await local.result(
                  row['id'] as String, 'review', e.message ?? 'ต้องตรวจสอบ');
            } else {
              return;
            }
          }
          changes.value++;
        }
      }
    } catch (_) {
      // Nothing is removed on timeout, process exit, logout or storage failure.
    } finally {
      _syncing = false;
    }
  }
}
