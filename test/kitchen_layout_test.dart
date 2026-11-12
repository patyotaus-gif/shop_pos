import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

TableOrder ticket(String id) => TableOrder(
      id: id,
      tableId: id,
      tableName: id,
      openedAt: DateTime(2026, 11, 12, 11, id == 'A1' ? 0 : 1),
      items: [
        TableOrderItem(
          id: 'food-$id',
          productId: 'food',
          productName: 'ข้าวกะเพราเห็ดรวมและไข่ดาว $id',
          price: 80,
          quantity: 2,
          notes: 'ไม่ใส่พริก แยกน้ำจิ้ม และไม่ใส่ถั่ว',
          kitchenStatus: KitchenStatus.sent,
        ),
      ],
    );

ShopOrder online(String id, OrderStatus status, {bool future = false}) =>
    ShopOrder(
      id: id,
      orderNumber: id,
      customerName: 'ลูกค้าทดสอบ',
      customerPhone: '',
      createdAt: DateTime(2026, 11, 12, 11, 2),
      pickupStartAt: future ? DateTime(2026, 11, 15, 12) : null,
      status: status,
      total: 80,
      items: [
        OrderItem(
            productId: 'food',
            productName: 'ข้าวผัดผักรวม',
            price: 80,
            quantity: 1,
            preparationNote: 'แยกน้ำจิ้ม ไม่ใส่ถั่ว'),
      ],
    );

Rect ticketRect(WidgetTester tester, String table) => tester.getRect(find
    .ancestor(of: find.text('โต๊ะ $table'), matching: find.byType(Material))
    .first);

Future<void> reach(WidgetTester tester, String label,
    {double delta = 150}) async {
  await tester.scrollUntilVisible(find.text(label).hitTestable(), delta,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  expect(find.text(label).hitTestable(), findsOneWidget);
}

void main() {
  setUpAll(() async {
    await (FontLoader(PokpokTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  // Real screen, font, layout and taps. Orders/settings and callbacks are local;
  // this suite never sends a print job or writes to a shop.
  for (final printer in [false, true]) {
    for (final width in [390.0, 768.0, 1440.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            'kitchen bounded tickets $width printer=$printer dark=$dark',
            (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final capture = GlobalKey();
          final readyCalls = <String>[];
          final updates = <OrderStatus>[];
          final sidebar = width >= 1000 ? 192.0 : 0.0;
          await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
              home: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sidebar > 0)
                      SizedBox(
                          width: sidebar,
                          child: const ColoredBox(color: Color(0xffeeeeee))),
                    Expanded(
                      child: KitchenScreen(
                        orders: Stream.value([ticket('A1'), ticket('A2')]),
                        onlineOrders: Stream.value([
                          online('ออนไลน์ 001', OrderStatus.accepted),
                          online('ออนไลน์ 002', OrderStatus.ready),
                          online('ออนไลน์ 003', OrderStatus.paid, future: true),
                          if (printer)
                            online('ออนไลน์ 004', OrderStatus.completed),
                        ]),
                        settings: Stream.value(
                            {'kitchenOutput': printer ? 'printer' : 'screen'}),
                        now: () => DateTime(2026, 11, 12, 11),
                        markReady: (order, item) async =>
                            readyCalls.add('$order/$item'),
                        updateOnlineStatus: (id, status) async =>
                            updates.add(status),
                      ),
                    ),
                  ]),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final first = ticketRect(tester, 'A1');
          final second = ticketRect(tester, 'A2');
          expect(first.width, lessThanOrEqualTo(600),
              reason: 'A ticket must not stretch across the tablet');
          expect(first.left, greaterThanOrEqualTo(sidebar));
          expect(second.right, lessThanOrEqualTo(width));
          for (final toggle in find.byType(SwitchListTile).evaluate()) {
            expect(tester.getSize(find.byWidget(toggle.widget)).width,
                lessThanOrEqualTo(600));
          }
          expect(find.text('แตะรายการอาหารเมื่อพร้อมเสิร์ฟ'), findsNWidgets(2));
          if (width >= 1000) {
            expect(second.top, closeTo(first.top, 1));
            expect(second.left, greaterThan(first.right));
          } else {
            expect(second.top, greaterThan(first.bottom));
            expect(second.left, closeTo(first.left, 1));
          }
          if (Platform.environment['KITCHEN_CAPTURES'] == '1') {
            await tester.runAsync(() async {
              final image = await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final dir = Directory('.remember/tmp/kitchen-layout')
                ..createSync(recursive: true);
              await File(
                      '${dir.path}/${width.toInt()}-${printer ? 'printer' : 'screen'}-${dark ? 'dark' : 'light'}.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.text('ข้าวกะเพราเห็ดรวมและไข่ดาว A2'));
          await tester.pumpAndSettle();
          expect(readyCalls, ['A2/food-A2']);
          await reach(tester, 'พร้อมรับ / เสิร์ฟแล้ว');
          await tester.tap(find.text('พร้อมรับ / เสิร์ฟแล้ว'));
          await tester.pumpAndSettle();
          expect(updates, [OrderStatus.ready]);
          // Ready, future and history groups must use the same bounded layout.
          for (final label in [
            'เลขออเดอร์ ออนไลน์ 002',
            'นัดรับวันถัดไป (1)'
          ]) {
            await reach(tester, label);
          }
          await tester.tap(find.text('นัดรับวันถัดไป (1)'));
          await tester.pumpAndSettle();
          await reach(tester, 'เลขออเดอร์ ออนไลน์ 003');
          final futureCard = find.ancestor(
              of: find.text('เลขออเดอร์ ออนไลน์ 003'),
              matching: find.byType(Card));
          expect(tester.getSize(futureCard).width, lessThanOrEqualTo(600));
          if (printer) {
            await reach(tester, 'ใบงานที่ปิดบิลหรือเสร็จแล้ว (1)', delta: -300);
            await tester.tap(find.text('ใบงานที่ปิดบิลหรือเสร็จแล้ว (1)'));
            await tester.pumpAndSettle();
            await reach(tester, 'เลขออเดอร์ ออนไลน์ 004');
            expect(
                tester
                    .getSize(find.ancestor(
                        of: find.text('เลขออเดอร์ ออนไลน์ 004'),
                        matching: find.byType(Card)))
                    .width,
                lessThanOrEqualTo(600));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('narrow workspace and large text use a single readable column',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final sidebar in [192.0, 640.0]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(sidebar == 192 ? 1.5 : 1)),
          child: child!,
        ),
        home: Row(children: [
          SizedBox(width: sidebar),
          Expanded(
              child: KitchenScreen(
                  orders: Stream.value([ticket('A1'), ticket('A2')]))),
        ]),
      ));
      await tester.pumpAndSettle();
      final first = ticketRect(tester, 'A1');
      final second = ticketRect(tester, 'A2');
      expect(first.width, lessThanOrEqualTo(600));
      expect(second.top, greaterThan(first.bottom));
      expect(second.left, closeTo(first.left, 1));
      expect(tester.takeException(), isNull);
    }
  });
}
