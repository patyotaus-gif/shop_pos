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
import 'package:shop_pos/widgets/app_viewport.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openPayment(WidgetTester tester,
      {required Size size,
      double scale = 1,
      double total = 75.91,
      bool showOmiseSandbox = false,
      bool searchBeforePayment = false,
      TargetPlatform platform = TargetPlatform.android,
      ValueChanged<PaymentResult?>? onResult}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light().copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: AppViewport(child: child!)),
      home: Scaffold(
          body: Builder(
              builder: (context) => Column(children: [
                    if (searchBeforePayment)
                      const TextField(
                          key: ValueKey('catalog-search'),
                          decoration:
                              InputDecoration(labelText: 'ค้นหาสินค้า')),
                    FilledButton(
                      onPressed: () async {
                        final result = await showPaymentSheet(context,
                            showOmiseSandbox: showOmiseSandbox,
                            total: total,
                            initialChannel: SalesChannel.takeaway);
                        onResult?.call(result);
                      },
                      child: const Text('ชำระเงิน'),
                    ),
                  ]))),
    ));
    if (searchBeforePayment) {
      await tester.enterText(
          find.byKey(const ValueKey('catalog-search')), 'ชา');
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
    }
    await tester.tap(find.text('ชำระเงิน'));
    await tester.pumpAndSettle();
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final exit in ['cancel', 'back', 'drag', 'confirm']) {
      testWidgets(
          'payment $exit leaves keyboard closed after search on $platform',
          (tester) async {
        var returned = false;
        PaymentResult? result;
        await openPayment(tester,
            size: const Size(1480, 924),
            total: 220,
            searchBeforePayment: true,
            platform: platform, onResult: (value) {
          returned = true;
          result = value;
        });
        final cash = find.widgetWithText(TextField, 'จำนวนเงินที่รับ');
        await tester.enterText(cash, '500');
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(find.text('฿280.00'), findsOneWidget);

        if (exit == 'back') {
          await tester.binding.handlePopRoute();
        } else if (exit == 'drag') {
          await tester.dragFrom(
              tester.getTopLeft(find.byType(DraggableScrollableSheet)) +
                  const Offset(100, 16),
              const Offset(0, 800));
        } else {
          final action =
              find.text(exit == 'confirm' ? 'ยืนยันการชำระเงิน' : 'ยกเลิก');
          await tester.ensureVisible(action);
          await tester.tap(action);
        }
        await tester.pumpAndSettle();

        expect(returned, isTrue);
        expect(result?.paid, exit == 'confirm' ? 500 : isNull);
        expect(cash, findsNothing);
        final search = tester.widget<EditableText>(find.descendant(
            of: find.byKey(const ValueKey('catalog-search')),
            matching: find.byType(EditableText)));
        expect(search.focusNode.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(search.controller.text, 'ชา');

        // Reopening checkout must still focus the amount for the next attempt.
        await tester.tap(find.text('ชำระเงิน'));
        await tester.pumpAndSettle();
        expect(cash, findsOneWidget);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('sandbox is hidden by default', (tester) async {
    await openPayment(tester, size: const Size(390, 844));
    expect(find.text('ทดลองชำระผ่าน Omise'), findsNothing);
    expect(find.text('เงินสด'), findsOneWidget);
    expect(find.text('เงินโอน'), findsOneWidget);
    expect(find.text('QR Code'), findsNothing);
  });

  testWidgets('legacy saved QR falls back to cash without confirming a sale',
      (tester) async {
    SharedPreferences.setMockInitialValues({'pos_last_payment_method': 'qr'});
    await openPayment(tester, size: const Size(390, 844));
    expect(find.text('QR Code'), findsNothing);
    expect(find.text('จำนวนเงินที่รับ'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'ยืนยันการชำระเงิน');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sandbox cancellation keeps the real bill unconfirmed',
      (tester) async {
    var returned = false;
    await openPayment(tester,
        size: const Size(390, 844),
        showOmiseSandbox: true,
        onResult: (_) => returned = true);
    final sandbox = find.text('ทดลองชำระผ่าน Omise');
    await tester.ensureVisible(sandbox);
    await tester.tap(sandbox);
    await tester.pumpAndSettle();
    expect(find.text('Omise Test Mode'), findsOneWidget);
    expect(find.textContaining('ยอดนี้ไม่ใช่ยอดบิลในตะกร้า'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('ยกเลิก')));
    await tester.pumpAndSettle();
    expect(returned, false);
    expect(find.text('Omise Test Mode'), findsNothing);
    expect(find.text('ยืนยันการชำระเงิน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.text('เงินโอน'));
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
    expect(find.text('ระบุจำนวนเต็ม 1–99'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(item.quantity, 12);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('landscape cashier sees payment immediately on $platform',
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
                  ]),
                  checkout: PosCheckoutPanel(
                      compact: true,
                      subtotal: 100,
                      discount: 0,
                      total: 100,
                      hasItems: true,
                      canDebt: false,
                      canDiscount: false,
                      onCheckout: () {},
                      onDebt: () {},
                      onDiscount: () {})))));
      await tester.tap(find.textContaining('ตะกร้า 2 หน่วย'));
      await tester.pumpAndSettle();
      // Payment must be visible without knowing to scroll an outer basket.
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
