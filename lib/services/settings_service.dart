import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

class SettingsService {
  static DocumentReference<Map<String, dynamic>> _doc() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('settings')
          .doc('shop');

  static Future<Map<String, dynamic>> getSettings() async {
    final snap = await _doc().get();
    return snap.data() ?? {};
  }

  static Future<String> getShopName() async {
    final data = await getSettings();
    return (data['name'] as String?)?.trim().isNotEmpty == true
        ? data['name'] as String
        : 'ร้านของชำ';
  }

  static Future<Map<String, String>> getShopInfo() async {
    final data = await getSettings();
    return {
      'name': (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'ร้านของชำ',
      'taxId': data['taxId'] as String? ?? '',
      'address': data['address'] as String? ?? '',
    };
  }

  static Future<void> saveSettings(Map<String, dynamic> data) async {
    await _doc().set(data, SetOptions(merge: true));
  }

  static Stream<Map<String, dynamic>> watchSettings() =>
      _doc().snapshots().map((s) => s.data() ?? {});

  static Future<Map<String, dynamic>> getLineSettings() async {
    final data = await getSettings();
    return {
      'lineUserId': data['lineUserId'] as String? ?? '',
      'lineNotifyEnabled': data['lineNotifyEnabled'] as bool? ?? false,
    };
  }

  static Future<void> saveLineSettings({
    required String lineUserId,
    required bool enabled,
  }) =>
      saveSettings({'lineUserId': lineUserId, 'lineNotifyEnabled': enabled});

  static Future<Map<String, String>> getPromptPaySettings() async {
    final data = await getSettings();
    return {
      'promptpayId': data['promptpayId'] as String? ?? '',
      'promptpayName': data['promptpayName'] as String? ?? '',
    };
  }

  static Future<void> savePromptPaySettings({
    required String promptpayId,
    required String promptpayName,
  }) =>
      saveSettings({
        'promptpayId': promptpayId,
        'promptpayName': promptpayName,
      });
}
