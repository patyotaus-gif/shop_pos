import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/staff_member.dart';
import 'auth_service.dart';

/// Staff profiles for the current shop + the locally-remembered "who's at
/// the till" selection. Attribution only — not an auth boundary.
class StaffService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('staff');

  // The active staff is per-device (which person is using this till right
  // now), so it lives in SharedPreferences, not Firestore.
  static const _activeKey = 'active_staff';

  static Stream<List<StaffMember>> watchAll() => _col()
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs
          .map((d) => StaffMember.fromFirestore(d.data(), d.id))
          .toList());

  static Future<List<StaffMember>> getAll() async {
    final snap = await _col().orderBy('createdAt').get();
    return snap.docs
        .map((d) => StaffMember.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<int> count() async => (await _col().get()).size;

  static Future<String> create({
    required String name,
    required String pin,
    StaffRole role = StaffRole.cashier,
  }) async {
    final ref = _col().doc();
    final staff = StaffMember(
      id: ref.id,
      name: name,
      pin: pin,
      role: role,
      createdAt: DateTime.now(),
    );
    await ref.set(staff.toFirestore());
    return ref.id;
  }

  static Future<void> update(StaffMember staff) async {
    await _col().doc(staff.id).update({
      'name': staff.name,
      'pin': staff.pin,
      'active': staff.active,
    });
  }

  static Future<void> delete(String id) async {
    await _col().doc(id).delete();
  }

  // ── Active staff (per-device, local) ──

  /// Returns the active staff {id, name} or null if none picked yet.
  static Future<({String id, String name})?> getActive() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey);
    if (raw == null) return null;
    final parts = raw.split('|');
    if (parts.length != 2) return null;
    return (id: parts[0], name: parts[1]);
  }

  static Future<void> setActive(StaffMember staff) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, '${staff.id}|${staff.name}');
  }

  static Future<void> clearActive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeKey);
  }
}
