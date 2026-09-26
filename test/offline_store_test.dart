import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_pos/services/offline_store.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Database db;
  late OfflineStore store;
  final permit = <String, dynamic>{
    'id': 'permit',
    'uid': 'cashier',
    'shopId': 'shop',
    'name': 'Cashier',
    'shopName': 'Shop',
    'products': [
      {'id': 'rice', 'stock': 3, 'stockMode': 'count'}
    ]
  };
  Map<String, dynamic> bill(String id, int quantity) => {
        'id': id,
        'items': [
          {'productId': 'rice', 'quantity': quantity}
        ]
      };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('offline-store-test');
    db = await databaseFactoryFfi.openDatabase('${dir.path}/cash.db',
        options:
            OpenDatabaseOptions(version: 1, onCreate: OfflineStore.create));
    store = OfflineStore(db);
    await store.savePermit(permit);
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test('paid receipts and status survive a database close and reopen',
      () async {
    await store.enqueue(permit, bill('sale1', 1));
    await db.close();
    db = await databaseFactoryFfi.openDatabase('${dir.path}/cash.db');
    store = OfflineStore(db);
    expect((await store.receipts()).single['status'], 'pending');
    await store.result('sale1', 'synced', 'stock needs review');
    expect((await store.receipts()).single['message'], 'stock needs review');
    expect((await store.permits()).single['uid'], 'cashier');
  });
  test('duplicate receipt and concurrent overselling do not corrupt the outbox',
      () async {
    await store.enqueue(permit, bill('sale1', 2));
    await expectLater(store.enqueue(permit, bill('sale1', 1)),
        throwsA(isA<DatabaseException>()));
    final outcomes = await Future.wait(['sale2', 'sale3'].map((id) async {
      try {
        await store.enqueue(permit, bill(id, 1));
        return true;
      } catch (_) {
        return false;
      }
    }));
    expect(outcomes.where((v) => v).length, 1);
    expect((await store.receipts()).length, 2);
  });
  test('already synced sales still reduce the original local stock snapshot',
      () async {
    await store.enqueue(permit, bill('sale1', 3));
    await store.result('sale1', 'synced', '');
    await expectLater(
        store.enqueue(permit, bill('sale2', 1)), throwsStateError);
    expect((await store.receipts()).length, 1);
  });
}
