import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/staff_member.dart';
import 'auth_service.dart';
import 'staff_access_service.dart';

/// Owner-managed profiles. Authentication and PIN verification are server-side.
class StaffService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('staff');

  static Stream<List<StaffMember>> watchAll() =>
      _col().orderBy('createdAt').snapshots().map((s) => s.docs
          .map((d) => StaffMember.fromFirestore(d.data(), d.id))
          .where((s) => s.active)
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
    final result = await StaffAccessService.call(
        'staffManage', {'name': name, 'pin': pin});
    return result['id'] as String;
  }

  static Future<void> update(StaffMember staff) async {
    await StaffAccessService.call('staffManage', {
      'id': staff.id,
      'name': staff.name,
      'pin': staff.pin,
      'active': staff.active
    });
  }

  static Future<void> delete(String id) async {
    final doc = await _col().doc(id).get();
    await StaffAccessService.call('staffManage',
        {'id': id, 'name': doc.data()?['name'] ?? 'พนักงาน', 'active': false});
  }

  // ── Active staff (per-device, local) ──

  /// Returns the active staff {id, name} or null if none picked yet.
  static Future<({String id, String name})?> getActive() async {
    if (!AuthService.isStaff) return null;
    final workspace = await StaffAccessService.workspace();
    return (id: AuthService.staffId!, name: workspace['staffName'] as String);
  }
}
