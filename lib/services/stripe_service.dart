import 'package:cloud_functions/cloud_functions.dart';

import '../models/shop.dart';
import 'auth_service.dart';

class StripeService {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// เรียก Firebase Function เพื่อสร้าง Stripe Checkout session
  /// คืน URL สำหรับเปิด browser ให้ลูกค้าชำระเงิน
  ///
  /// [tier] เป็น Pokpok tier ที่จะ subscribe (solo/lite/full/restaurant).
  /// [billingCycle] = 'monthly' หรือ 'yearly'.
  /// [locations] สำหรับ Restaurant tier เท่านั้น — จะคูณราคา; default = 1.
  static Future<String?> createCheckoutUrl({
    required ShopTier tier,
    String billingCycle = 'monthly',
    int locations = 1,
  }) async {
    try {
      final callable = _functions.httpsCallable('createCheckoutSession');
      final result = await callable.call({
        'shopId': AuthService.shopId,
        'tier': tier.name,
        'billingCycle': billingCycle,
        'locations': locations,
      });
      return result.data['url'] as String?;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('สร้าง checkout ไม่สำเร็จ: ${e.message}');
    }
  }
}
