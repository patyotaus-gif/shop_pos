import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/mobile_sales_workspace.dart';
import 'package:shop_pos/widgets/pos_basket.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';

void main() {
  setUp(() =>
      SharedPreferences.setMockInitialValues({'test-shortcut': 'discount'}));
  testWidgets(
      'opening cart dismisses search focus and keeps payment above keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final searchFocus = FocusNode();
    addTearDown(searchFocus.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
          appBar: AppBar(title: const Text('ขาย')),
          body: MobileSalesWorkspace(
            itemCount: 1,
            total: 35,
            catalog: ListView(children: [TextField(focusNode: searchFocus)]),
            basket: PosBasket(
                itemCount: 1, itemBuilder: (_, i) => const Text('Brownie')),
            checkout: PosCheckoutPanel(
                compact: true,
                subtotal: 35,
                total: 35,
                discount: 0,
                hasItems: true,
                canDiscount: true,
                canDebt: true,
                onCheckout: () {},
                onDiscount: () {},
                onDebt: () {}),
          ),
        )));
    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(searchFocus.hasFocus, isTrue);
    await tester.tap(find.textContaining('ตะกร้า 1 หน่วย'));
    await tester.pumpAndSettle();
    expect(searchFocus.hasFocus, isFalse);
    final pay = find.byKey(const ValueKey('checkout-pay'));
    expect(pay.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(pay).dy, lessThanOrEqualTo(844 - 260));
    expect(tester.takeException(), isNull);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final staff in [false, true]) {
      for (final size in [
        const Size(320, 568),
        const Size(568, 320),
        const Size(914, 411)
      ]) {
        testWidgets('checkout stays visible: $platform staff=$staff size=$size',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var payments = 0;
          await tester.pumpWidget(MaterialApp(
            theme: PokpokTheme.light().copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!),
            home: Scaffold(
              appBar: AppBar(title: const Text('ขาย')),
              bottomNavigationBar: const SizedBox(height: 64),
              body: Column(children: [
                if (staff) const SizedBox(height: 48, child: Text('พนักงาน')),
                Expanded(
                    child: MobileSalesWorkspace(
                  itemCount: 20,
                  total: 700,
                  catalog: const SizedBox(),
                  basket: PosBasket(
                      itemCount: 20,
                      itemBuilder: (_, i) => ListTile(title: Text('สินค้า $i')),
                      loyalty: staff
                          ? null
                          : const ListTile(title: Text('เพิ่มลูกค้าสะสมแต้ม'))),
                  checkout: PosCheckoutPanel(
                      preferenceKey: 'test-shortcut',
                      compact: true,
                      horizontalTotal: size.height < 500,
                      subtotal: 700,
                      discount: 0,
                      total: 700,
                      hasItems: true,
                      canDiscount: !staff,
                      canDebt: !staff,
                      onCheckout: () => payments++,
                      onDebt: () {},
                      onDiscount: () {}),
                )),
              ]),
            ),
          ));
          await tester.tap(find.textContaining('ตะกร้า 20 หน่วย'));
          await tester.pumpAndSettle();
          final pay = find.byKey(const ValueKey('checkout-pay'));
          expect(pay.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(pay);
          expect(payments, 1);
          if (find.byType(PosBasket).evaluate().isNotEmpty &&
              tester.getSize(find.byType(PosBasket)).height > 50) {
            await tester.drag(find.byType(PosBasket), const Offset(0, -300));
            await tester.pumpAndSettle();
            expect(pay.hitTestable(), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
