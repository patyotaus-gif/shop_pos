import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/services/sale_display_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/theme/sale_button_palette.dart';
import 'package:shop_pos/widgets/product_image.dart';
import 'package:shop_pos/widgets/product_picker_sheet.dart';
import 'package:shop_pos/widgets/sale_display_controls.dart';
import 'package:shop_pos/widgets/sale_product_grid.dart';

const products = [
  Product(
      id: '1',
      name: 'ข้าวกะเพราหมูสับไข่ดาวพิเศษ',
      barcode: '1',
      price: 80,
      salePrice: 70,
      stock: 20,
      category: 'อาหารจานเดียว'),
  Product(
      id: '2',
      name: 'ข้าวผัดกุ้ง',
      barcode: '2',
      price: 90,
      stock: 12,
      category: 'อาหารจานเดียว'),
  Product(
      id: '3',
      name: 'ชาไทยเย็น',
      barcode: '3',
      price: 45,
      stock: 30,
      category: 'เครื่องดื่ม'),
  Product(
      id: '4',
      name: 'โกโก้เย็น',
      barcode: '4',
      price: 50,
      stock: 0,
      category: 'เครื่องดื่ม'),
  Product(
      id: '5',
      name: 'เค้กช็อกโกแลต',
      barcode: '5',
      price: 85,
      stock: 9,
      category: 'ขนม'),
  Product(
      id: '6',
      name: 'บราวนี่',
      barcode: '6',
      price: 40,
      stock: 9,
      category: 'ขนม'),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(PokpokTheme.fontFamily)
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  test('reload keeps mode and category colors; a different shop stays isolated',
      () async {
    final a = SaleDisplayController('shop-A');
    await a.load();
    expect(a.value.mode, SaleDisplayMode.photos);
    await a.save(a.value
        .withMode(SaleDisplayMode.names)
        .withColor('เครื่องดื่ม', 'teal'));
    final reloaded = SaleDisplayController('shop-A');
    await reloaded.load();
    expect(reloaded.value.mode, SaleDisplayMode.names);
    expect(reloaded.value.categoryColors, {'เครื่องดื่ม': 'teal'});
    final other = SaleDisplayController('shop-B');
    await other.load();
    expect(other.value.mode, SaleDisplayMode.photos);
    expect(other.value.categoryColors, isEmpty);
    await reloaded.save(reloaded.value.withColor('เครื่องดื่ม', null));
    await a.load();
    expect(a.value.categoryColors, isEmpty);
  });

  test('invalid stored settings report load failure and a choice repairs them',
      () async {
    final c = SaleDisplayController('broken');
    SharedPreferences.setMockInitialValues({c.storageKey: 'not JSON'});
    await c.load();
    expect(c.loadFailed, isTrue);
    expect(c.value.mode, SaleDisplayMode.photos);
    await c.save(c.value.withMode(SaleDisplayMode.names));
    expect(c.loadFailed, isFalse);
    final next = SaleDisplayController('broken');
    await next.load();
    expect(next.value.mode, SaleDisplayMode.names);
    final sanitized = SaleDisplaySettings.decode(
        '{"mode":"other","categoryColors":{"bad":"neon","ok":"blue"}}');
    expect(sanitized.mode, SaleDisplayMode.photos);
    expect(sanitized.categoryColors, {'ok': 'blue'});
  });

  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      testWidgets('name buttons and color choices $width dark=$dark',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 960);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final c = SaleDisplayController('visual');
        await c.load();
        await c.save(c.value
            .withMode(SaleDisplayMode.names)
            .withColor('อาหารจานเดียว', 'amber')
            .withColor('เครื่องดื่ม', 'teal')
            .withColor('ขนม', 'wine'));
        final boundary = GlobalKey();
        final rootBoundary = GlobalKey();
        var count = 0;
        await tester.pumpWidget(MaterialApp(
          theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
          builder: (_, child) =>
              RepaintBoundary(key: rootBoundary, child: child!),
          home: SaleDisplayScope(
              controller: c,
              child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                    appBar: AppBar(title: const Text('ขายหน้าร้าน')),
                    body: StatefulBuilder(
                        builder: (context, update) => Column(children: [
                              const SaleDisplayControls(categories: [
                                'อาหารจานเดียว',
                                'เครื่องดื่ม',
                                'ขนม'
                              ]),
                              Expanded(
                                  child: SaleProductGrid(
                                      itemCount: products.length,
                                      products: products,
                                      itemBuilder: (_, i) => SaleProductCard(
                                          product: products[i],
                                          unavailableLabel:
                                              products[i].stock == 0
                                                  ? 'หมด'
                                                  : null,
                                          onTap: products[i].stock == 0
                                              ? null
                                              : () => update(() => count++)))),
                              Text('รายการที่เลือก: $count'),
                            ])),
                  ))),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProductImage), findsNothing);
        expect(find.text('฿70.00'), findsOneWidget);
        expect(find.text('฿80.00'), findsOneWidget);
        final first = find.byType(SaleProductCard).first;
        expect(tester.getSize(first).width, lessThanOrEqualTo(200));
        final nameRect = tester.getRect(find.text(products.first.name));
        expect(tester.getRect(first).contains(nameRect.bottomRight), isTrue);
        await tester.tap(first);
        await tester.pump();
        expect(find.text('รายการที่เลือก: 1'), findsOneWidget);
        if (width >= 390) {
          await tester.tap(find.byType(SaleProductCard).at(3));
          expect(count, 1);
        }
        if (Platform.environment['SALE_CAPTURES'] == '1' && width != 320) {
          await capture(tester, boundary,
              '${width.toInt()}-names-${dark ? 'dark' : 'light'}');
        }
        await tester.tap(find.text('รูปภาพสินค้า'));
        await tester.pumpAndSettle();
        expect(find.byType(ProductImage), findsWidgets);
        expect(find.text('รายการที่เลือก: 1'), findsOneWidget);
        await tester.tap(find.text('ปุ่มชื่อสินค้า'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('สีปุ่ม'));
        await tester.pumpAndSettle();
        expect(find.text('สีปุ่มตามหมวดหมู่'), findsOneWidget);
        await tester.tap(find.text('ฟ้า'));
        await tester.pumpAndSettle();
        expect(c.value.categoryColors['อาหารจานเดียว'], 'blue');
        if (Platform.environment['SALE_CAPTURES'] == '1' &&
            width == 390 &&
            !dark) {
          await capture(tester, rootBoundary, '390-colors');
        }
        await tester.tap(find.text('เสร็จแล้ว'));
        await tester.pumpAndSettle();
        expect(find.text('รายการที่เลือก: 1'), findsOneWidget);
        final card = tester.widget<Card>(
            find.descendant(of: first, matching: find.byType(Card)).first);
        final cardContext = tester.element(first);
        expect(card.color, SaleButtonPalette.background(cardContext, 'blue'));
        final ink =
            Theme.of(cardContext).colorScheme.onSurface.computeLuminance();
        for (final color in SaleDisplaySettings.colorNames) {
          final fill = SaleButtonPalette.background(cardContext, color)
              .computeLuminance();
          final contrast = ink > fill
              ? (ink + .05) / (fill + .05)
              : (fill + .05) / (ink + .05);
          expect(contrast, greaterThanOrEqualTo(4.5),
              reason: '$color theme=$dark');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('long names and categories stay readable at 200 percent text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = SaleDisplayController('large');
    await c.load();
    await c.save(c.value.withMode(SaleDisplayMode.names));
    final long = products.first.copyWith(
        name: 'ข้าวกะเพราเห็ดรวมใส่ไข่ดาวแบบสุกพิเศษ',
        category: 'อาหารจานเดียวสำหรับมื้อกลางวัน');
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: SaleDisplayScope(
            controller: c,
            child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: SaleProductGrid(
                      itemCount: 1,
                      products: [long],
                      itemBuilder: (_, i) =>
                          SaleProductCard(product: long, onTap: () {})),
                )))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(find.text(long.name));
    expect(label.maxLines, isNull);
    expect(label.overflow, isNull);
    final tile = tester.getRect(find.byType(SaleProductCard));
    expect(tile.contains(tester.getRect(find.text(long.name)).bottomRight),
        isTrue);
  });

  testWidgets(
      'table draft survives changing modes and confirms original items/prices',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(768, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = SaleDisplayController('table');
    await c.load();
    final tableCapture = GlobalKey();
    var saved = false;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (_, child) =>
            RepaintBoundary(key: tableCapture, child: child!),
        home: Scaffold(
            body: Builder(
          builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SaleDisplayScope(
                      controller: c,
                      child: TableProductPicker(
                          products: Stream.value(products),
                          save: (items, _) async {
                            expect(items, hasLength(1));
                            expect(items.single.productId, '1');
                            expect(items.single.quantity, 2);
                            expect(items.single.unitPrice, 70);
                            saved = true;
                          }))),
              child: const Text('open')),
        ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปุ่มชื่อสินค้า'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductImage), findsNothing);
    expect(find.text('เลือก 1 ชิ้น'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-1')));
    await tester.pumpAndSettle();
    expect(find.text('เลือก 2 ชิ้น'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    if (Platform.environment['SALE_CAPTURES'] == '1') {
      await capture(tester, tableCapture, '768-table-picker');
    }
    await tester.tap(find.text('เพิ่มลงโต๊ะ · ฿140.00'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('color settings stay usable at 320px with 200 percent text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = SaleDisplayController('large-controls');
    await c.load();
    await c.save(c.value.withMode(SaleDisplayMode.names));
    const category = 'อาหารจานเดียวสำหรับมื้อกลางวัน';
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: SaleDisplayScope(
            controller: c,
            child: const Scaffold(
                body: SingleChildScrollView(
                    child: SaleDisplayControls(categories: [category]))))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สีปุ่ม'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('ฟ้า'));
    await tester.tap(find.text('ฟ้า'));
    await tester.pumpAndSettle();
    expect(c.value.categoryColors[category], 'blue');
    await tester.tap(find.text('เสร็จแล้ว'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name mode keeps offline base prices and disabled actions',
      (tester) async {
    final c = SaleDisplayController('offline');
    await c.load();
    await c.save(c.value.withMode(SaleDisplayMode.names));
    var count = 0;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: SaleDisplayScope(
            controller: c,
            child: Scaffold(
                body: SaleProductGrid(
              itemCount: 2,
              products: products,
              itemBuilder: (_, i) => SaleProductCard(
                  product: products.first,
                  showPromotion: false,
                  onTap: i == 0 ? () => count++ : null),
            )))));
    await tester.pumpAndSettle();
    expect(find.text('฿80.00'), findsNWidgets(2));
    expect(find.text('฿70.00'), findsNothing);
    expect(find.byIcon(Icons.block), findsOneWidget);
    await tester.tap(find.byType(SaleProductCard).at(1));
    expect(count, 0);
    await tester.tap(find.byType(SaleProductCard).first);
    expect(count, 1);
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.remember/tmp/sale-display/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
