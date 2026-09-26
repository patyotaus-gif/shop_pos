import 'dart:convert';
import 'package:sqflite/sqflite.dart';

/// Durable outbox. A cash receipt is shown only after this transaction commits.
class OfflineStore {
  OfflineStore(this.db);
  final Database db;
  static Future<void> create(Database db, int version) async {
    await db.execute(
        'CREATE TABLE permits (id TEXT PRIMARY KEY, uid TEXT NOT NULL, shop TEXT NOT NULL, label TEXT NOT NULL, data TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE receipts (id TEXT PRIMARY KEY, permit TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL, message TEXT NOT NULL DEFAULT \'\')');
  }

  Future<void> savePermit(Map<String, dynamic> p) async {
    await db.insert(
        'permits',
        {
          'id': p['id'],
          'uid': p['uid'],
          'shop': p['shopId'],
          'label': '${p['shopName']} · ${p['name']}',
          'data': jsonEncode(p)
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> permits() => db.query('permits');
  Future<List<Map<String, Object?>>> receipts({String? permit}) =>
      db.query('receipts',
          where: permit == null ? null : 'permit = ?',
          whereArgs: permit == null ? null : [permit],
          orderBy: 'rowid DESC');
  Future<void> enqueue(
      Map<String, dynamic> permit, Map<String, dynamic> bill) async {
    await db.transaction((tx) async {
      final rows = await tx
          .query('receipts', where: 'permit = ?', whereArgs: [permit['id']]);
      final used = <String, int>{};
      for (final row in rows) {
        for (final line
            in jsonDecode(row['payload'] as String)['items'] as List) {
          used.update(
              line['productId'] as String, (n) => n + (line['quantity'] as int),
              ifAbsent: () => line['quantity'] as int);
        }
      }
      for (final line in bill['items'] as List) {
        used.update(
            line['productId'] as String, (n) => n + (line['quantity'] as int),
            ifAbsent: () => line['quantity'] as int);
      }
      for (final product in permit['products'] as List) {
        if (product['stockMode'] != 'recipe' &&
            (used[product['id']] ?? 0) > (product['stock'] as num)) {
          throw StateError('สต็อกในเครื่องไม่พอ: ${product['name']}');
        }
      }
      await tx.insert('receipts', {
        'id': bill['id'],
        'permit': permit['id'],
        'payload': jsonEncode(bill),
        'status': 'pending',
        'message': ''
      });
    });
  }

  Future<void> result(String id, String status, String message) async {
    await db.update('receipts', {'status': status, 'message': message},
        where: 'id = ?', whereArgs: [id]);
  }
}
