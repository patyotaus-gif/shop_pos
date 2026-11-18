import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/widgets/side_navigation_shell.dart';
import 'package:shop_pos/widgets/app_viewport.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> openShell(WidgetTester tester, Size size,
      {double textScale = 1, bool reduceMotion = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: PokpokTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: AppViewport(child: child!),
      ),
      home: const _ShellHarness(),
    ));
  }

  testWidgets('rotating between phone and sidebar layouts preserves cart',
      (tester) async {
    await openShell(tester, const Size(375, 812));
    await tester.tap(find.byKey(const ValueKey('add-item')));
    await tester.pump();
    tester.view.physicalSize = const Size(812, 375);
    await tester.pumpAndSettle();
    expect(find.text('สินค้าในตะกร้า 1'), findsOneWidget);
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpAndSettle();
    expect(find.text('สินค้าในตะกร้า 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing the menu preserves the page and saves the preference',
      (tester) async {
    await openShell(tester, const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('add-item')));
    await tester.pump();
    final before = tester.getTopLeft(find.byKey(const ValueKey('add-item'))).dx;
    await tester.tap(find.byKey(const ValueKey('toggle-sidebar')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('add-item'))).dx,
        lessThan(before));
    expect(find.text('สินค้าในตะกร้า 1'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('sidebar-collapsed'),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching pages preserves the active cart state',
      (tester) async {
    await openShell(tester, const Size(1200, 900));
    await tester.tap(find.byKey(const ValueKey('add-item')));
    await tester.pump();
    expect(find.text('สินค้าในตะกร้า 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-ออเดอร์')));
    await tester.pump();
    expect(find.text('หน้าออเดอร์'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-ขาย')));
    await tester.pump();
    expect(find.text('สินค้าในตะกร้า 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('phone-navigation')), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('add-item'))).dx,
        greaterThan(192));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all destinations remain reachable on a small landscape screen',
      (tester) async {
    await openShell(tester, const Size(568, 320), textScale: 2);
    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ตั้งค่า'), 150);
    await tester.tap(find.text('ตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.text('หน้าตั้งค่า'), findsOneWidget);
    expect(find.text('เพิ่มเติม'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone tabs move the pill and show only the selected label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openShell(tester, const Size(375, 812));
    expect(find.text('99+'), findsOneWidget);
    final nav = find.byKey(const ValueKey('phone-navigation'));
    final pill = find.byKey(const ValueKey('phone-navigation-indicator'));
    expect(tester.getSize(nav).height, 64);
    expect(tester.getBottomRight(nav).dy, 812 - 34);
    expect(find.text('ออเดอร์'), findsNothing);
    final initial = tester.getRect(pill);
    await tester.tap(find.byTooltip('ออเดอร์'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final middle = tester.getRect(pill);
    await tester.pumpAndSettle();
    expect(middle.left, greaterThan(initial.left));
    expect(middle.left, lessThan(tester.getRect(pill).left));
    expect(find.text('ออเดอร์'), findsOneWidget);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('ขาย'), findsNothing);
    expect(find.text('หน้าออเดอร์'), findsOneWidget);
    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 60));
    await tester.pumpAndSettle();
    expect(find.text('หน้าออเดอร์'), findsOneWidget);
    await tester.tap(find.byTooltip('ขาย'));
    await tester.pumpAndSettle();
    expect(find.text('สินค้าในตะกร้า 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('reduced motion immediately selects the destination on a narrow phone',
      (tester) async {
    await openShell(tester, const Size(320, 720), reduceMotion: true);
    final pill = find.byKey(const ValueKey('phone-navigation-indicator'));
    await tester.tap(find.byTooltip('ครัว'));
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(pill).dx,
        closeTo(tester.getCenter(find.byTooltip('ครัว')).dx, 0.1));
    expect(find.text('หน้าครัว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ShellHarness extends StatefulWidget {
  const _ShellHarness();
  @override
  State<_ShellHarness> createState() => _ShellHarnessState();
}

class _ShellHarnessState extends State<_ShellHarness> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => SideNavigationShell(
        selectedIndex: selected,
        onSelected: (index) => setState(() => selected = index),
        items: [
          const AppNavigationItem(
            screen: _CartPage(),
            icon: Icons.point_of_sale_outlined,
            selectedIcon: Icons.point_of_sale,
            label: 'ขาย',
          ),
          for (final label in [
            'ออเดอร์',
            'โต๊ะ',
            'ครัว',
            'สินค้า',
            'รายงาน',
            'ลูกค้าเครดิต',
            'AI',
            'QR สั่งอาหาร',
            'ตั้งค่า',
          ])
            AppNavigationItem(
              screen: Scaffold(body: Center(child: Text('หน้า$label'))),
              icon: Icons.storefront_outlined,
              selectedIcon: Icons.storefront,
              label: label,
              badgeCount: label == 'ออเดอร์' ? 123 : 0,
            ),
        ],
      );
}

class _CartPage extends StatefulWidget {
  const _CartPage();
  @override
  State<_CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<_CartPage> {
  int count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('add-item'),
            onPressed: () => setState(() => count++),
            child: Text('สินค้าในตะกร้า $count'),
          ),
        ),
      );
}
