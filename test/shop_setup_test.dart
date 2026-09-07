import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/widgets/shop_setup_checklist.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ShopDatabase.overrideShop = null);
  testWidgets('practice checkout cannot create a real sale or deduct inventory',
      (tester) async {
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.collection('shops').doc('demo');
    await tester.pumpWidget(const MaterialApp(home: DemoCheckoutScreen()));
    await tester.tap(find.text('เพิ่ม'));
    await tester.pump();
    await tester.tap(find.text('จำลองรับเงินสดครบยอด'));
    await tester.pump();
    expect(find.text('ฝึกคิดเงินสำเร็จ · ไม่ใช่ใบเสร็จจริง'), findsOneWidget);
    expect((await db.collection('shops/demo/sales').get()).docs, isEmpty);
    expect((await db.collection('shops/demo/products').get()).docs, isEmpty);
  });
  testWidgets('restaurant checklist reflects setup and includes tables',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('demo');
    ShopDatabase.overrideShop = shop;
    await shop.set({'tier': 'restaurant'});
    await shop.collection('products').doc('tea').set({'name': 'tea'});
    await shop
        .collection('settings')
        .doc('shop')
        .set({'onboardingCashReady': true});
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(child: ShopSetupChecklist()))));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มโต๊ะแรก'), findsOneWidget);
    expect(find.text('เริ่มตั้งค่าร้าน (2/4)'), findsOneWidget);
    await shop.collection('tables').doc('one').set({'name': '1'});
    await tester.pumpAndSettle();
    expect(find.text('เริ่มตั้งค่าร้าน (3/4)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
