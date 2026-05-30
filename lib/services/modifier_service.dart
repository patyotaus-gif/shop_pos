import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/modifier_group.dart';
import 'auth_service.dart';

class ModifierService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('modifierGroups');

  static Stream<List<ModifierGroup>> watchAll() => _col()
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs
          .map((d) => ModifierGroup.fromFirestore(d.data(), d.id))
          .toList());

  static Future<List<ModifierGroup>> getByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    // Firestore 'in' tops out at 30 ids per query (which is plenty for a
    // single product's modifier groups — typical menu items have 2-3).
    final snap = await _col()
        .where(FieldPath.documentId, whereIn: ids.take(30).toList())
        .get();
    return snap.docs
        .map((d) => ModifierGroup.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<String> create(ModifierGroup group) async {
    final ref = _col().doc();
    await ref.set(group.toFirestore());
    return ref.id;
  }

  static Future<void> update(ModifierGroup group) async {
    await _col().doc(group.id).update(group.toFirestore());
  }

  static Future<void> delete(String id) async {
    await _col().doc(id).delete();
  }
}
