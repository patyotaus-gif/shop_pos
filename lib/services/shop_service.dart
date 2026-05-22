import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/shop.dart';
import 'auth_service.dart';

class ShopService {
  static DocumentReference<Map<String, dynamic>> _doc() =>
      FirebaseFirestore.instance.collection('shops').doc(AuthService.shopId);

  static Stream<Shop?> watchCurrentShop() => _doc()
      .snapshots()
      .map((s) => s.exists ? Shop.fromFirestore(s.data()!, s.id) : null);

  static Future<Shop?> getCurrentShop() async {
    final snap = await _doc().get();
    if (!snap.exists) return null;
    return Shop.fromFirestore(snap.data()!, snap.id);
  }

  /// สร้าง shop document ตอนสมัครสมาชิก — ทดลองใช้ 14 วัน
  static Future<void> createShop({
    required String name,
    required String email,
  }) async {
    final trialEndsAt = DateTime.now().add(const Duration(days: 14));
    final shop = Shop(
      id: AuthService.shopId!,
      name: name,
      email: email,
      subscriptionStatus: SubscriptionStatus.trial,
      trialEndsAt: trialEndsAt,
      createdAt: DateTime.now(),
    );
    await _doc().set(shop.toFirestore());
  }

  static Future<void> updateName(String name) async {
    await _doc().update({'name': name});
  }
}
