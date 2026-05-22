import 'package:cloud_functions/cloud_functions.dart';
import 'auth_service.dart';

class StripeService {
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// เรียก Firebase Function เพื่อสร้าง Stripe Checkout session
  /// คืน URL สำหรับเปิด browser ให้ลูกค้าชำระเงิน
  static Future<String?> createCheckoutUrl(String plan) async {
    try {
      final callable = _functions.httpsCallable('createCheckoutSession');
      final result = await callable.call({
        'shopId': AuthService.shopId,
        'plan': plan,
      });
      return result.data['url'] as String?;
    } on FirebaseFunctionsException catch (e) {
      throw Exception('สร้าง checkout ไม่สำเร็จ: ${e.message}');
    }
  }
}
