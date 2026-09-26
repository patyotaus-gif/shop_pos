import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/order_modifier.dart';
import 'package:shop_pos/services/offline_service.dart';
import 'package:shop_pos/services/offline_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late OfflineStore store;
  late Map<String, dynamic> permit;
  const cart = [
    CartItem(
        product: Product(
            id: 'rice', name: 'Rice', barcode: '', price: 50, stock: 10))
  ];
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options:
            OpenDatabaseOptions(version: 1, onCreate: OfflineStore.create));
    store = OfflineStore(db);
    OfflineService.useTestStore(store);
    final now = DateTime.now();
    permit = {
      'id': 'permit',
      'uid': 'cashier',
      'shopId': 'shop',
      'name': 'Cashier',
      'shopName': 'Shop',
      'issuedAt': now.subtract(const Duration(minutes: 1)).toIso8601String(),
      'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
      'products': [
        {'id': 'rice', 'stock': 10, 'stockMode': 'count'}
      ]
    };
    await store.savePermit(permit);
    final salt = List<int>.filled(32, 7);
    final hash = base64Encode(await (await Pbkdf2(
                macAlgorithm: Hmac.sha256(), iterations: 100000, bits: 256)
            .deriveKey(
                secretKey: SecretKey(utf8.encode('123456')), nonce: salt))
        .extractBytes());
    FlutterSecureStorage.setMockInitialValues({
      'offline-permit': jsonEncode({
        'secret': 'test',
        'salt': salt,
        'hash': hash,
        'attempts': 0,
        'lockedUntil': 0,
        'lastSeen': now.millisecondsSinceEpoch
      })
    });
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async {
    OfflineService.useTestStore(null);
    await db.close();
  });
  test('offline pricing matches server zero-floor and per-line rounding', () {
    const negative = CartItem(
        product: Product(
            id: 'rice', name: 'Rice', barcode: '', price: 50, stock: 10),
        modifiers: [
          OrderModifier(
              groupId: 'size',
              groupName: 'Size',
              optionId: 'small',
              optionName: 'Small',
              priceAdjust: -60)
        ]);
    const fractional = CartItem(
        product: Product(
            id: 'tiny', name: 'Tiny', barcode: '', price: 1.006, stock: 10));
    expect(OfflineService.cartTotal([negative]), 0);
    expect(OfflineService.cartTotal([fractional, fractional]), 2.02);
  });
  test('five incorrect offline PINs lock even the correct PIN', () async {
    final profile = (await store.permits()).single;
    for (var i = 0; i < 5; i++) {
      await expectLater(
          OfflineService.unlock(profile, '000000'), throwsStateError);
    }
    await expectLater(
        OfflineService.unlock(profile, '123456'), throwsStateError);
    expect(await store.receipts(), isEmpty);
  });
  test(
      'unlock permits cash outbox; locked and expired sessions cannot create receipts',
      () async {
    await expectLater(
        OfflineService.checkout(permit, cart, 50), throwsStateError);
    await OfflineService.unlock((await store.permits()).single, '123456');
    await OfflineService.checkout(permit, cart, 50);
    expect((await store.receipts()).length, 1);
    await expectLater(
        OfflineService.checkout({
          ...permit,
          'expiresAt': DateTime.now()
              .subtract(const Duration(seconds: 1))
              .toIso8601String()
        }, cart, 50),
        throwsStateError);
    OfflineService.lock();
    await expectLater(
        OfflineService.checkout(permit, cart, 50), throwsStateError);
    expect((await store.receipts()).length, 1);
  });
  test('an unresolved online payment blocks a new offline receipt', () async {
    await OfflineService.unlock((await store.permits()).single, '123456');
    SharedPreferences.setMockInitialValues(
        {'pending-checkout-shop': 'unresolved'});
    await expectLater(
        OfflineService.checkout(permit, cart, 50), throwsStateError);
    expect(await store.receipts(), isEmpty);
  });
}
