import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // สร้าง channel สำหรับออเดอร์ใหม่ (Android-only — iOS ใช้ APNs ตรงๆ)
    const channel = AndroidNotificationChannel(
      'new_orders',
      'ออเดอร์ใหม่',
      description: 'แจ้งเตือนเมื่อมีออเดอร์ออนไลน์ใหม่',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  // เรียกหลัง login — ขอ permission + บันทึก token ใน Firestore
  static Future<void> initFCM(String shopId) async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token != null) {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .set({'fcmToken': token}, SetOptions(merge: true));
    }

    // token เปลี่ยน (เช่น reinstall) → อัปเดต Firestore
    messaging.onTokenRefresh.listen((newToken) {
      FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .set({'fcmToken': newToken}, SetOptions(merge: true));
    });

    // แสดง notification เมื่อแอปอยู่ foreground
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) _showLocal(n.title ?? '', n.body ?? '', 'new_orders');
    });
  }

  static Future<void> showLowStock(String productName, int stock) async {
    await init();
    await _showLocal(
      'สินค้าใกล้หมด: $productName',
      'เหลือสต็อก $stock ชิ้น',
      'low_stock',
    );
  }

  static Future<void> _showLocal(
      String title, String body, String channelId) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'new_orders' ? 'ออเดอร์ใหม่' : 'สินค้าใกล้หมด',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(title.hashCode, title, body, details);
  }
}
