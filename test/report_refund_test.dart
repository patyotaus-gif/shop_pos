import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/report_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

void main() {
  setUpAll(() async {
    final fonts = FontLoader(PokpokTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    await fonts.load();
  });

  testWidgets('confirming a refund from the bill sheet actually runs it',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.collection('shops').doc('test');
    addTearDown(() => ShopDatabase.overrideShop = null);
    await ShopDatabase.overrideShop!.set({'name': 'test', 'tier': 'full'});
    final sale = Sale(
        id: 'debt-1',
        items: const [
          SaleItem(
              productId: 'p',
              productName: 'เลย์',
              price: 20,
              quantity: 1,
              subtotal: 20)
        ],
        total: 20,
        discount: 0,
        paid: 0,
        change: 0,
        createdAt: DateTime.now(),
        isDebt: true,
        customerName: 'ทดสอบ');
    await ShopDatabase.overrideShop!
        .collection('sales')
        .doc(sale.id)
        .set(sale.toFirestore());

    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light(),
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const ReportScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ประวัติการขาย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ค้างชำระ: ทดสอบ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('คืนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เหตุผลที่คืนเงิน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกรายการผิด').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันคืนเงิน'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // No Firebase in tests, so the refund call fails; what matters is that it
    // was attempted and the result reached the owner instead of vanishing.
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
