import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/screens/product_form_screen.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/app_viewport.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShopDatabase.overrideShop =
        FakeFirebaseFirestore().collection('shops').doc('layout');
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  void setView(WidgetTester tester, Size size, double bottom,
      {double left = 0, double right = 0}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding =
        FakeViewPadding(top: 24, bottom: bottom, left: left, right: right);
    tester.view.viewPadding =
        FakeViewPadding(top: 24, bottom: bottom, left: left, right: right);
    addTearDown(tester.view.reset);
  }

  for (final scenario in [
    (name: 'Android buttons', size: const Size(393, 852), bottom: 48.0),
    (name: 'iPhone gesture', size: const Size(390, 844), bottom: 34.0),
    (name: 'tablet', size: const Size(800, 1100), bottom: 24.0),
  ]) {
    testWidgets('${scenario.name}: pushed product form save stays tappable',
        (tester) async {
      setView(tester, scenario.size, scenario.bottom);
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: AppViewport.builder,
        home: Builder(
            builder: (context) => Scaffold(
                  body: Center(
                      child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const ProductFormScreen())),
                    child: const Text('เปิดฟอร์ม'),
                  )),
                )),
      ));
      await tester.tap(find.text('เปิดฟอร์ม'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'เพิ่มสินค้า');
      await tester.scrollUntilVisible(save, 400,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(save).dy,
          lessThanOrEqualTo(scenario.size.height - scenario.bottom));
      expect(save.hitTestable(), findsOneWidget);
      // Empty form validation proves the real button receives the tap.
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested safe areas and navigation reserve the bottom only once',
      (tester) async {
    setView(tester, const Size(390, 844), 34);
    await tester.pumpWidget(MaterialApp(
      builder: AppViewport.builder,
      home: Scaffold(
        body: SafeArea(child: Container(key: const ValueKey('body'))),
        bottomNavigationBar: NavigationBar(
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.store), label: 'ขาย'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'ตั้งค่า'),
          ],
        ),
      ),
    ));
    expect(tester.getSize(find.byType(NavigationBar)).height, 64);
    expect(tester.getBottomRight(find.byType(NavigationBar)).dy, 810);
    expect(tester.getBottomRight(find.byKey(const ValueKey('body'))).dy, 746);
  });

  testWidgets('modal sheet stays above navigation and follows keyboard insets',
      (tester) async {
    setView(tester, const Size(393, 852), 48);
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.dark(),
      builder: AppViewport.builder,
      home: Builder(
          builder: (context) => Scaffold(
                  body: Center(
                child: TextButton(
                  child: const Text('เปิด'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => Padding(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.viewInsetsOf(context).bottom),
                      child: SafeArea(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const TextField(),
                        FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('บันทึก')),
                      ])),
                    ),
                  ),
                ),
              ))),
    ));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'บันทึก');
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(804));
    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding(top: 24);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(552));
    expect(tester.getBottomRight(save).dy, greaterThan(540));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'landscape respects side cutouts and keeps top inset for app bars',
      (tester) async {
    setView(tester, const Size(852, 393), 24, left: 44, right: 24);
    await tester.pumpWidget(MaterialApp(
      builder: AppViewport.builder,
      home: Scaffold(
        appBar: AppBar(title: const Text('หน้า')),
        body: SafeArea(child: Container(key: const ValueKey('content'))),
      ),
    ));
    final rect = tester.getRect(find.byKey(const ValueKey('content')));
    expect(rect.left, 44);
    expect(rect.right, 828);
    expect(rect.bottom, 369);
    expect(rect.top, 24 + kToolbarHeight);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'product stock labels clear expanded section (${dark ? 'dark' : 'light'})',
        (tester) async {
      setView(tester, const Size(393, 852), 48);
      await tester.pumpWidget(MaterialApp(
        theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: AppViewport(child: child!),
        ),
        home: const ProductFormScreen(),
      ));
      final stock = find.widgetWithText(TextFormField, 'สต๊อกเริ่มต้น *');
      await tester.scrollUntilVisible(stock, 300,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(stock);
      await tester.pumpAndSettle();
      final tile = find.byType(ExpansionTile);
      expect(tester.getTopLeft(stock).dy - tester.getBottomRight(tile).dy,
          greaterThanOrEqualTo(16));
      final renderedBorder = find.descendant(
          of: tile,
          matching: find.byWidgetPredicate(
            (w) => w is Material && w.shape == const Border(),
          ));
      expect(renderedBorder, findsWidgets);
      // Open the optional lot fields and check their floating labels have room.
      final toggle =
          find.widgetWithText(SwitchListTile, 'ติดตามล็อตและวันหมดอายุ');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final lot = find.widgetWithText(
          TextFormField, 'ล็อตของสต๊อกเริ่มต้น (เมื่อมีสต๊อก)');
      final expiry =
          find.widgetWithText(TextFormField, 'วันหมดอายุของล็อตเริ่มต้น');
      await tester.ensureVisible(expiry);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(expiry).dy - tester.getBottomRight(lot).dy,
          greaterThanOrEqualTo(16));
      expect(tester.takeException(), isNull);
    });
  }
}
