import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'staff_access_service.dart';

/// Pending mutations survive screen dismissal and app restart. Their request ID
/// and payload stay fixed until the server confirms the result.
class StaffInventoryApi {
  const StaffInventoryApi();
  bool can(String permission) => StaffAccessService.can(permission);
  Future<Map<String, dynamic>> call(String action, Map<String, dynamic> data) =>
      StaffAccessService.work(action, data);
  String _key(String productId) =>
      'staff-stock-${AuthService.shopId}-${AuthService.currentUser?.uid}-$productId';
  Future<Map<String, dynamic>?> pending(String productId) async {
    final value =
        (await SharedPreferences.getInstance()).getString(_key(productId));
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  Future<void> savePending(
      String productId, Map<String, dynamic> request) async {
    if (!await (await SharedPreferences.getInstance())
        .setString(_key(productId), jsonEncode(request))) {
      throw StateError('เก็บรายการรอยืนยันไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  Future<void> clearPending(String productId) async {
    if (!await (await SharedPreferences.getInstance())
        .remove(_key(productId))) {
      throw StateError(
          'ล้างรายการรอยืนยันไม่สำเร็จ กรุณาตรวจผลก่อนทำรายการใหม่');
    }
  }
}
