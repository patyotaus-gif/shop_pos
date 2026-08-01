import 'dart:typed_data';

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

    // ออเดอร์ค้างยืนยันเกิน 5 นาที — channel แยกจาก new_orders ด้วย
    // vibration pattern ที่ต่างชัดเจน จะได้สังเกตว่าด่วนกว่าปกติ
    final unconfirmedChannel = AndroidNotificationChannel(
      'unconfirmed_order',
      'ออเดอร์ค้างยืนยัน',
      description:
          'แจ้งเตือนเมื่อออเดอร์ที่จ่ายเงินแล้วยังไม่ได้กดยืนยันเกิน 5 นาที',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 400]),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(unconfirmedChannel);

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

    // แสดง notification เมื่อแอปอยู่ foreground — ใช้ channel เดียวกับที่
    // FCM payload ระบุมา ไม่งั้น escalation (unconfirmed_order) จะโชว์บน
    // new_orders แทน แล้ว vibration pattern ที่ตั้งใจแยกไว้จะไม่ทำงาน
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n != null) {
        _showLocal(
            n.title ?? '', n.body ?? '', n.android?.channelId ?? 'new_orders');
      }
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

  // Channel id → display name, kept in sync with the channels registered
  // in init() above. Harmless if stale for an already-created channel
  // (Android ignores the name after creation), but should stay correct.
  static const _channelNames = {
    'new_orders': 'ออเดอร์ใหม่',
    'unconfirmed_order': 'ออเดอร์ค้างยืนยัน',
    'low_stock': 'สินค้าใกล้หมด',
  };

  static Future<void> _showLocal(
      String title, String body, String channelId) async {
    await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelNames[channelId] ?? channelId,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(title.hashCode, title, body, details);
  }
}
