import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/shop.dart';
import 'auth_service.dart';

class ShopService {
  static DocumentReference<Map<String, dynamic>> _doc() =>
      FirebaseFirestore.instance.collection('shops').doc(AuthService.shopId);

  /// Unambiguous referral-code alphabet — no 0/O or 1/I/L so codes are
  /// easy to read aloud and type. 6 chars ≈ 1.3B combos; collision risk
  /// is negligible at this scale and the applyReferral function matches
  /// exactly anyway.
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String _generateReferralCode() {
    final rng = Random.secure();
    return List.generate(
        6, (_) => _codeAlphabet[rng.nextInt(_codeAlphabet.length)]).join();
  }

  static Stream<Shop?> watchCurrentShop() => _doc()
      .snapshots()
      .map((s) => s.exists ? Shop.fromFirestore(s.data()!, s.id) : null);

  static Future<Shop?> getCurrentShop() async {
    final snap = await _doc().get();
    if (!snap.exists) return null;
    return Shop.fromFirestore(snap.data()!, snap.id);
  }

  /// สร้าง shop document ตอนสมัครสมาชิก — ทดลองใช้ 60 วัน
  ///
  /// 60 วันคือ trial มาตรฐานสำหรับทุก tier — ยาวพอให้ลูกค้าได้ใช้ผ่าน
  /// monthly cycle (รับเงินเดือน, จ่ายบิล) และตัดสินใจจริงๆ ไม่ใช่แค่
  /// ลองวันสองวันแล้วลืม. ถ้า founder/sales agent อยากต่อให้ลูกค้า
  /// บางราย ใช้ trial extension UI ใน Phase D ได้
  static Future<void> createShop({
    required String name,
    required String email,
    ShopTier tier = ShopTier.full,
    ShopType? shopType,
    int locations = 1,
    String? policyVersion,
  }) async {
    final trialEndsAt = DateTime.now().add(const Duration(days: 60));
    final shop = Shop(
      id: AuthService.shopId!,
      name: name,
      email: email,
      subscriptionStatus: SubscriptionStatus.trial,
      tier: tier,
      shopType: shopType ?? tier.derivedShopType,
      locations: locations,
      trialEndsAt: trialEndsAt,
      createdAt: DateTime.now(),
      referralCode: _generateReferralCode(),
    );
    final data = shop.toFirestore();
    // Record the Terms/Privacy version accepted at signup (PDPA trail).
    if (policyVersion != null) {
      data['consent'] = {
        'policyVersion': policyVersion,
        'acceptedAt': FieldValue.serverTimestamp(),
      };
    }
    await _doc().set(data);
  }

  static Future<void> updateName(String name) async {
    await _doc().update({'name': name});
  }

  /// Redeem a referral code entered at signup. Delegates to the
  /// applyReferral Cloud Function which (with admin rights) extends BOTH
  /// the referrer's and this shop's trial by 30 days — the client can't
  /// write to another shop's doc directly. Returns true on success.
  ///
  /// Safe to call even with an empty/invalid code; the function no-ops
  /// and we swallow errors so a bad code never blocks signup.
  static Future<bool> applyReferral(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return false;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('applyReferral');
      final res = await fn.call({'code': trimmed});
      return res.data['applied'] == true;
    } catch (_) {
      return false;
    }
  }
}
