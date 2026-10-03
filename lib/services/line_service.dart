import 'package:cloud_functions/cloud_functions.dart';
import 'auth_service.dart';

class LineService {
  static const officialAccountUrl = 'https://lin.ee/V8eWC8Tl';

  static bool isValidUserId(String value) =>
      RegExp(r'^U[0-9a-fA-F]{32}$').hasMatch(value.trim());

  /// Unlike background notifications, a manual test must expose failures.
  static Future<void> testConnection() async {
    final shopId = AuthService.shopId;
    if (shopId == null || AuthService.isStaff) {
      throw StateError('กรุณาเข้าสู่ระบบเจ้าของร้าน');
    }
    final result = await _fn('sendLineMessage').call({
      'shopId': shopId,
      'message': '✅ ทดสอบการแจ้งเตือนจาก Pokpok POS',
    });
    requireAccepted(result.data);
  }

  static void requireAccepted(dynamic result) {
    if (result is Map && result['skipped'] == true) {
      throw StateError('ยังไม่ได้เปิดการแจ้งเตือน LINE');
    }
    if (result is! Map || result['success'] != true) {
      throw StateError(
          'LINE ไม่รับข้อความ กรุณาตรวจการเชื่อมต่อและการบล็อกบัญชี Pokpok');
    }
  }

  static HttpsCallable _fn(String name) =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable(name);

  /// ส่ง text message ไปยัง LINE ของเจ้าของร้าน
  static Future<void> sendMessage(String message) async {
    final shopId = AuthService.shopId;
    if (shopId == null) return;
    try {
      await _fn('sendLineMessage').call({'shopId': shopId, 'message': message});
    } catch (e) {
      // LINE ไม่ได้ตั้งค่า หรือปิดใช้งาน — ไม่ throw เพื่อไม่กระทบ flow หลัก
    }
  }

  /// ส่งแจ้งเตือนออเดอร์ใหม่
  static Future<void> notifyNewOrder({
    required String customerName,
    required int itemCount,
    required double total,
  }) =>
      sendMessage(
        '🛒 ออเดอร์ใหม่!\n'
        'ลูกค้า: $customerName\n'
        'สินค้า: $itemCount ชิ้น\n'
        'ยอด: ฿${total.toStringAsFixed(2)}\n'
        'เปิดแอป Pokpok เพื่อยืนยัน',
      );

  /// ส่งแจ้งเตือนสินค้าใกล้หมด
  static Future<void> notifyLowStock(String productName, int stock) =>
      sendMessage('⚠️ สินค้าใกล้หมด!\n$productName เหลือ $stock ชิ้น');

  /// ส่งสรุปยอดขายประจำวัน
  static Future<void> notifyDailySummary({
    required double revenue,
    required int billCount,
    required double profit,
  }) =>
      sendMessage(
        '📊 สรุปยอดขายวันนี้\n'
        'รายได้: ฿${revenue.toStringAsFixed(2)}\n'
        'จำนวน: $billCount บิล\n'
        'กำไร: ฿${profit.toStringAsFixed(2)}',
      );
}
