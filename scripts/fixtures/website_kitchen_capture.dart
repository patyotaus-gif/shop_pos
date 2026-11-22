// Render the production kitchen/sidebar with isolated demonstration inputs.
// Run with flutter test after copying into test/ in an isolated source snapshot.
// No Firebase initialization, database writes, printing or payment callbacks.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/side_navigation_shell.dart';

void main() {
  testWidgets('capture current kitchen with synthetic tickets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
    tester.view.physicalSize = const Size(1480, 924);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final name in ['Regular', 'SemiBold', 'Bold']) {
      await (FontLoader(PokpokTheme.fontFamily)
        ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-$name.ttf'))).load();
    }
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final tickets = [
      for (var table = 1; table <= 2; table++)
        TableOrder(id: 'demo-$table', tableId: 'demo-table-$table',
          tableName: '0$table', openedAt: DateTime(2026, 11, 22, 12, table),
          items: [
            TableOrderItem(id: 'demo-pasta-$table', productId: 'demo-pasta',
              productName: table == 1 ? 'พาสต้ากุ้งและมะเขือเทศ' : 'พาสต้าแซลมอนและบรอกโคลี',
              price: table == 1 ? 80 : 120, quantity: 2,
              notes: table == 1 ? 'ไม่ใส่พริก' : null,
              kitchenStatus: KitchenStatus.sent),
            const TableOrderItem(id: 'demo-spaghetti', productId: 'demo-spaghetti',
              productName: 'สปาเกตตีซอสมะเขือเทศ', price: 70, quantity: 1,
              kitchenStatus: KitchenStatus.sent),
          ]),
    ];
    final kitchen = KitchenScreen(orders: Stream.value(tickets),
      onlineOrders: Stream.value(<ShopOrder>[]), settings: Stream.value({}),
      printJobs: Stream.value({}), lastClosedAt: Stream<DateTime?>.value(null),
      saveOutput: (_) async {}, markReady: (_, __) async {},
      updateOnlineStatus: (_, __) async {}, now: () => DateTime(2026, 11, 22, 12, 5));
    // Same menu labels/icons as the restaurant workspace in lib/main.dart.
    final navigation = [
      ('ขาย', Icons.table_restaurant_outlined, Icons.table_restaurant),
      ('ออเดอร์', Icons.shopping_bag_outlined, Icons.shopping_bag),
      ('สินค้า', Icons.inventory_2_outlined, Icons.inventory_2),
      ('รายงาน', Icons.bar_chart_outlined, Icons.bar_chart),
      ('เครื่องมือส่งเสริมการขาย', Icons.local_offer_outlined, Icons.local_offer),
      ('ครัว', Icons.soup_kitchen_outlined, Icons.soup_kitchen),
      ('ผู้ช่วยร้าน', Icons.auto_awesome_outlined, Icons.auto_awesome),
      ('QR สั่งอาหาร', Icons.qr_code_2_outlined, Icons.qr_code_2),
      ('ตั้งค่า', Icons.settings_outlined, Icons.settings),
    ];
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: MaterialApp(
      debugShowCheckedModeBanner: false, theme: PokpokTheme.light(),
      home: SideNavigationShell(selectedIndex: 5, onSelected: (_) {}, items: [
        for (var i = 0; i < navigation.length; i++)
          AppNavigationItem(screen: i == 5 ? kitchen : const SizedBox.shrink(),
            label: navigation[i].$1, icon: navigation[i].$2,
            selectedIcon: navigation[i].$3),
      ]))));
    await tester.runAsync(() async {
      for (final asset in ['assets/icon/icon.png', 'assets/brand/pokpok-wordmark.png']) {
        await precacheImage(AssetImage(asset), boundaryKey.currentContext!);
      }
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('โต๊ะ 01'), findsOneWidget);
    expect(find.text('โต๊ะ 02'), findsOneWidget);
    final boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    void repaint(RenderObject object) { object.markNeedsPaint(); object.visitChildren(repaint); }
    repaint(boundary);
    await tester.pump();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Platform.environment['KITCHEN_CAPTURE_OUTPUT']!;
      await File(output).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    debugDisableShadows = oldShadows;
  });
}
