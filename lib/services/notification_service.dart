import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _initialized = true;
  }

  static Future<void> showLowStock(String productName, int stock) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'low_stock',
        'สินค้าใกล้หมด',
        channelDescription: 'แจ้งเตือนเมื่อสินค้าเหลือน้อย',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(
      productName.hashCode,
      'สินค้าใกล้หมด: $productName',
      'เหลือสต็อก $stock ชิ้น',
      details,
    );
  }
}
