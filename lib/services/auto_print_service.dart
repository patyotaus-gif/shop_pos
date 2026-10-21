import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import 'bluetooth_printer_service.dart';

class AutoPrintService {
  static const channel = MethodChannel('app.pokpok.pos/auto_print');
  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('auto_print_device_v1');
    if (saved != null) return saved;
    final id = const Uuid().v4();
    if (!await prefs.setString('auto_print_device_v1', id)) {
      throw StateError('บันทึกเครื่องหลักไม่สำเร็จ');
    }
    return id;
  }

  static Future<Map<String, dynamic>> call(String name, String shopId,
      [Map<String, dynamic> data = const {}]) async {
    final result = await FirebaseFunctions.instanceFor(
            region: 'asia-southeast1')
        .httpsCallable(name,
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
        .call({'shopId': shopId, ...data});
    return Map<String, dynamic>.from(result.data as Map);
  }

  static Future<void> start(
      {required bool kitchen, required bool receipts}) async {
    if (!BluetoothPrinterService.supported) {
      throw StateError('ใช้ Android เป็นเครื่องหลักพิมพ์ Bluetooth ในรุ่นนี้');
    }
    final shopId = AuthService.shopId;
    if (shopId == null || AuthService.isStaff) {
      throw StateError('ให้เจ้าของร้านเปิดโหมดเครื่องหลัก');
    }
    final printer = await BluetoothPrinterService.saved();
    if (printer == null) {
      throw StateError('เลือกและบันทึกเครื่องพิมพ์ Bluetooth ก่อน');
    }
    // Preflight permission, pairing and radio without opening a print socket.
    final devices = await BluetoothPrinterService.pairedDevices();
    if (!devices.any((d) => d.address == printer.address)) {
      throw StateError('ไม่พบเครื่องพิมพ์ที่บันทึกไว้ กรุณาจับคู่ใหม่');
    }
    final state = await localState();
    if (state['running'] == true) {
      throw StateError('หยุดเครื่องหลักก่อนเปลี่ยนการตั้งค่า');
    }
    final notifications = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (await notifications?.requestNotificationsPermission() == false) {
      throw StateError(
          'อนุญาตการแจ้งเตือนเพื่อแสดงสถานะเครื่องหลักและปุ่มหยุดก่อน');
    }
    final id = await deviceId();
    final config = await call('configureAutoPrint', shopId, {
      'deviceId': id,
      'deviceName': printer.name,
      'enabled': true,
      'kitchen': kitchen,
      'receipts': receipts,
    });
    try {
      await channel.invokeMethod<void>('start', {
        'shopId': shopId,
        'deviceId': id,
        'session': config['session'],
        'address': printer.address,
        'name': printer.name,
        'paperMm': printer.paperMm,
      });
    } catch (_) {
      await call(
          'configureAutoPrint', shopId, {'deviceId': id, 'enabled': false});
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> localState() async =>
      BluetoothPrinterService.supported
          ? Map<String, dynamic>.from(
              await channel.invokeMapMethod('state') ?? {})
          : {'running': false};

  static Future<void> stopLocal() async {
    if (BluetoothPrinterService.supported) {
      await channel.invokeMethod<void>('stop');
    }
  }

  static Future<void> stopShop() async {
    await stopLocal();
    final shopId = AuthService.shopId;
    if (shopId != null) {
      await call('configureAutoPrint', shopId,
          {'deviceId': await deviceId(), 'enabled': false});
    }
  }

  static CollectionReference<Map<String, dynamic>> jobs(String shopId) =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('autoPrintJobs');

  static String errorMessage(Object e) => e is FirebaseFunctionsException
      ? (e.message ?? 'ติดต่อคิวพิมพ์ไม่ได้ ลองใหม่อีกครั้ง')
      : BluetoothPrinterService.errorMessage(e);

  static bool sessionLost(Object e) =>
      e is FirebaseFunctionsException &&
      ['permission-denied', 'unauthenticated', 'failed-precondition']
          .contains(e.code);

  static bool matchesUser(String shopId) =>
      FirebaseAuth.instance.currentUser?.uid == shopId;
}
