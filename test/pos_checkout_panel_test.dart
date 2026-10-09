import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';
import 'package:shop_pos/widgets/side_navigation_shell.dart';

Widget checkout(
        {bool staff = false,
        bool empty = false,
        double discount = 0,
        double total = 100,
        VoidCallback? onPay,
        VoidCallback? onDiscount,
        VoidCallback? onDebt}) =>
    PosCheckoutPanel(
        compact: true,
        subtotal: total + discount,
        discount: discount,
        total: total,
        hasItems: !empty,
        canDiscount: !staff,
        canDebt: !staff,
        onCheckout: onPay ?? () {},
        onDiscount: onDiscount ?? () {},
        onDebt: onDebt ?? () {});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'iPhone shell reserves home indicator once and compact checkout stays within 80px',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              padding: const EdgeInsets.only(top: 47, bottom: 34),
              viewPadding: const EdgeInsets.only(top: 47, bottom: 34)),
          child: child!),
      home: SideNavigationShell(selectedIndex: 0, onSelected: (_) {}, items: [
        AppNavigationItem(
            label: 'ขาย',
            icon: Icons.store_outlined,
            selectedIcon: Icons.store,
            screen: Scaffold(
                body: Column(children: [
              const Expanded(child: SizedBox()),
              checkout()
            ]))),
        const AppNavigationItem(
            label: 'สินค้า',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: SizedBox()),
      ]),
    ));
    await tester.pumpAndSettle();
    final nav = tester.getRect(find.byType(NavigationBar));
    final panel = tester.getRect(find.byType(PosCheckoutPanel));
    expect(nav.height, 64 + 34);
    expect(panel.height, lessThanOrEqualTo(80));
    expect(panel.bottom, nav.top);
    expect(nav.bottom, 844);
    expect(tester.getSize(find.byKey(const ValueKey('checkout-pay'))).height,
        greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'discount and credit stay reachable while staff and empty carts cannot invoke restricted actions',
      (tester) async {
    var paid = 0, discounted = 0, debt = 0;
    Widget app({bool staff = false, bool empty = false}) => MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: checkout(
                    staff: staff,
                    empty: empty,
                    discount: 10,
                    total: 90,
                    onPay: () => paid++,
                    onDiscount: () => discounted++,
                    onDebt: () => debt++))));
    await tester.pumpWidget(app());
    expect(find.text('฿90.00'), findsOneWidget);
    expect(find.text('รวม ฿100.00 · ส่วนลด ฿10.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('checkout-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ส่วนลด'));
    await tester.pumpAndSettle();
    expect(discounted, 1);
    await tester.tap(find.byKey(const ValueKey('checkout-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ขายเชื่อ'));
    await tester.pumpAndSettle();
    expect(debt, 1);
    await tester.tap(find.byKey(const ValueKey('checkout-pay')));
    expect(paid, 1);
    await tester.pumpWidget(app(staff: true));
    expect(find.byKey(const ValueKey('checkout-more')), findsNothing);
    await tester.pumpWidget(app(empty: true));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('checkout-pay')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('checkout-more')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<String>>(
                find.widgetWithText(PopupMenuItem<String>, 'ขายเชื่อ'))
            .enabled,
        isFalse);
  });

  testWidgets(
      'small screens, large text and large totals remain readable; standalone checkout keeps safe inset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [320.0, 375.0, 430.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 700),
                  textScaler: const TextScaler.linear(2),
                  padding: const EdgeInsets.only(bottom: 34)),
              child: Scaffold(
                  body: Align(
                      alignment: Alignment.bottomCenter,
                      child: checkout(total: 12345678.99, discount: 100))))));
      await tester.pumpAndSettle();
      expect(find.text('฿12,345,678.99'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
          tester.getBottomRight(find.byKey(const ValueKey('checkout-pay'))).dy,
          lessThanOrEqualTo(666));
    }
  });
}
