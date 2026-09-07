import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/widgets/side_navigation_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> openShell(WidgetTester tester, Size size,
      {double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const _ShellHarness(),
    ));
  }

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
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.getTopLeft(find.byKey(const ValueKey('add-item'))).dx,
        greaterThan(192));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all destinations remain reachable on a small landscape screen',
      (tester) async {
    await openShell(tester, const Size(568, 320), textScale: 2);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('nav-ตั้งค่า')),
      150,
      scrollable: find.descendant(
        of: find.byKey(const PageStorageKey('side-navigation')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('nav-ตั้งค่า')));
    await tester.pump();
    expect(find.text('หน้าตั้งค่า'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone sidebar shows order count and accessible selected state',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await openShell(tester, const Size(375, 812));
    expect(find.text('99+'), findsOneWidget);
    final selected = tester.getSemantics(find.bySemanticsLabel('ขาย'));
    expect(
        selected,
        matchesSemantics(
          label: 'ขาย',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ));
    expect(find.bySemanticsLabel('ออเดอร์, 123 ออเดอร์ใหม่'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
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
            'ลูกหนี้',
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
