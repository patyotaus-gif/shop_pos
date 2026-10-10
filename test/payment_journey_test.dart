import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/payment_sheet.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';
import 'package:shop_pos/widgets/mobile_sales_workspace.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openPayment(WidgetTester tester,
      {required Size size,
      double scale = 1,
      double total = 75.91,
      ValueChanged<PaymentResult?>? onResult}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Builder(
              builder: (context) => FilledButton(
                    onPressed: () async {
                      final result = await showPaymentSheet(context,
                          total: total, initialChannel: SalesChannel.takeaway);
                      onResult?.call(result);
                    },
                    child: const Text('ชำระเงิน'),
                  ))),
    ));
    await tester.tap(find.text('ชำระเงิน'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'cash blocks short payment, calculates change and returns takeaway channel',
      (tester) async {
    PaymentResult? result;
    await openPayment(tester,
        size: const Size(390, 844), onResult: (r) => result = r);
    final confirm = find.widgetWithText(FilledButton, 'ยืนยันการชำระเงิน');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '75');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pump();
    expect(find.text('฿24.09'), findsOneWidget);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.paid, 100);
    expect(result?.method, PaymentMethod.cash);
    expect(result?.salesChannel, SalesChannel.takeaway);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'transfer can be confirmed without a reference and cancel returns no payment',
      (tester) async {
    PaymentResult? result;
    await openPayment(tester,
        size: const Size(320, 568), onResult: (r) => result = r);
    await tester.tap(find.text('โอนเงิน'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'ได้รับเงินแล้ว ยืนยัน');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.method, PaymentMethod.transfer);
    expect(result?.paid, 75.91);
    expect(result?.ref, isNull);
    await tester.tap(find.text('ชำระเงิน'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ยกเลิก'));
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'exact cash remains payable when summed prices have binary rounding noise',
      (tester) async {
    PaymentResult? result;
    await openPayment(tester,
        size: const Size(390, 844),
        total: 35.10 + 75.20,
        onResult: (r) => result = r);
    final exact = find.widgetWithText(ActionChip, '฿110.30');
    await tester.ensureVisible(exact);
    await tester.tap(exact);
    await tester.pump();
    final confirm = find.widgetWithText(FilledButton, 'ยืนยันการชำระเงิน');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(find.text('(ขาด ฿0.00)'), findsNothing);
    expect(find.text('฿0.00'), findsOneWidget);
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(result?.paid, 110.30);
  });

  testWidgets(
      'quantity edit stays usable after rotating with keyboard and large text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    var item = CartItem(
        product: const Product(
            id: 'tea', name: 'ชาไทย', barcode: '', price: 35.5, stock: 50));
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, set) => ListView(children: [
                      CartItemTile(
                          item: item,
                          onRemove: () {},
                          onQtyChanged: (q) =>
                              set(() => item = item.copyWith(quantity: q))),
                    ])))));
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewInsets = const FakeViewPadding(bottom: 170);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    final submit = find.widgetWithText(FilledButton, 'ตกลง');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(item.quantity, 1);
    expect(find.text('กรอกจำนวนเต็มตั้งแต่ 1 ขึ้นไป'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(item.quantity, 12);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        'landscape cashier can reach payment by swiping the basket on $platform',
        (tester) async {
      tester.view.physicalSize = const Size(914, 411);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light().copyWith(platform: platform),
          home: Scaffold(
              appBar: AppBar(title: const Text('ขาย')),
              body: MobileSalesWorkspace(
                  itemCount: 2,
                  total: 100,
                  catalog: const SizedBox(),
                  basket: Column(children: [
                    Expanded(
                        child: ListView(children: [
                      for (var i = 0; i < 2; i++)
                        CartItemTile(
                            item: CartItem(
                                product: Product(
                                    id: '$i',
                                    name: 'รายการ $i',
                                    barcode: '',
                                    price: 50,
                                    stock: 10)),
                            onQtyChanged: (_) {},
                            onRemove: () {}),
                    ])),
                    PosCheckoutPanel(
                        compact: true,
                        subtotal: 100,
                        discount: 0,
                        total: 100,
                        hasItems: true,
                        canDebt: false,
                        canDiscount: false,
                        onCheckout: () {},
                        onDebt: () {},
                        onDiscount: () {}),
                  ])))));
      await tester.tap(find.textContaining('ตะกร้า 2 ชิ้น'));
      await tester.pumpAndSettle();
      // Exercise a real drag, not ensureVisible (which can scroll hidden parents).
      for (var i = 0; i < 3; i++) {
        await tester.dragFrom(const Offset(450, 340), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(FilledButton, 'ชำระเงิน').hitTestable(),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(800, 1024)
  ]) {
    testWidgets('payment reachable with keyboard and large text at $size',
        (tester) async {
      await openPayment(tester, size: size, scale: 2);
      // Approximate the native numeric keyboard, including landscape height.
      tester.view.viewInsets =
          FakeViewPadding(bottom: size.height < 500 ? 170 : 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'ยืนยันการชำระเงิน');
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      expect(confirm.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('ชำระเงิน'), findsOneWidget);
    });
  }
}
