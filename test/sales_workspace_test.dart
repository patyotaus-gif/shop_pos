import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/screens/tables_screen.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';
import 'package:shop_pos/screens/restaurant_sales_screen.dart';
import 'package:shop_pos/services/sale_display_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/pos_catalog.dart';
import 'package:shop_pos/widgets/pos_basket.dart';
import 'package:shop_pos/widgets/pos_checkout_panel.dart';
import 'package:shop_pos/widgets/pos_sales_workspace.dart';
import 'package:shop_pos/widgets/pos_sales_header.dart';
import 'package:shop_pos/widgets/sale_display_controls.dart';
import 'package:shop_pos/widgets/sale_product_grid.dart';

const _products = [
  Product(
      id: '1',
      name: 'ข้าวกะเพราหมูสับไข่ดาว',
      barcode: '123',
      price: 70,
      stock: 20,
      category: 'อาหาร',
      isPinned: true),
  Product(
      id: '2',
      name: 'ชาไทยเย็น',
      barcode: '456',
      price: 45,
      stock: 12,
      category: 'เครื่องดื่ม'),
  Product(
      id: '3',
      name: 'โกโก้เย็น',
      barcode: '789',
      price: 50,
      stock: 0,
      category: 'เครื่องดื่ม'),
  Product(
      id: '4',
      name: 'บราวนี่',
      barcode: '101',
      price: 40,
      stock: 5,
      category: 'รายการโปรด'),
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

  testWidgets(
      'favorites, category names, barcode search and availability share one stream',
      (tester) async {
    final controller = SaleDisplayController('catalog');
    await controller.load();
    final source = StreamController<List<Product>>();
    var loads = 0, scans = 0, bundles = 0;
    final added = <String>[];
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: SaleDisplayScope(
            controller: controller,
            child: Scaffold(
                body: PosCatalog(
                    loadProducts: () {
                      loads++;
                      return source.stream;
                    },
                    onAdd: (p) => added.add(p.id),
                    onScan: () => scans++,
                    onChooseBundle: () => bundles++)))));
    source.add(_products);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sales-tab-favorites')));
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductCard), findsOneWidget);
    await tester.tap(find.byType(SaleProductCard));
    expect(added, ['1']);
    final pref = SaleDisplayController('catalog');
    await pref.load();
    expect(pref.value.catalogTab, 'favorites');
    // Search respects the selected category, including remembered favorites.
    await tester.enterText(find.byKey(const ValueKey('sales-search')), '456');
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบสินค้าที่ค้นหาในหมวดนี้'), findsOneWidget);
    expect(find.text('ชาไทยเย็น'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('sales-tab-all')));
    await tester.pumpAndSettle();
    expect(find.text('ชาไทยเย็น'), findsOneWidget);
    expect(find.textContaining('บาร์โค้ด 456'), findsOneWidget);
    expect(find.textContaining('คงเหลือ 12'), findsOneWidget);
    await tester.tap(find.byTooltip('สแกนบาร์โค้ด'));
    expect(scans, 1);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sales-search')))
            .controller!
            .text,
        '456');
    await tester.tap(find.byKey(const ValueKey('sale-search-2')));
    await tester.pumpAndSettle();
    expect(added, ['1', '2']);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sales-search')))
            .controller!
            .text,
        isEmpty);
    expect(find.byTooltip('สแกนบาร์โค้ด'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const ValueKey('sales-tab-category:รายการโปรด')));
    await tester
        .tap(find.byKey(const ValueKey('sales-tab-category:รายการโปรด')));
    await tester.pumpAndSettle();
    expect(find.text('บราวนี่'), findsOneWidget);
    expect(find.text('ข้าวกะเพราหมูสับไข่ดาว'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('sales-tab-all')));
    await tester.tap(find.byKey(const ValueKey('sales-tab-all')));
    await tester.enterText(find.byKey(const ValueKey('sales-search')), '789');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sale-search-3')), findsOneWidget);
    expect(find.textContaining('คงเหลือ 0'), findsOneWidget);
    expect(find.textContaining('\nหมด'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sale-search-3')));
    expect(added, ['1', '2']);
    await tester.tap(find.byTooltip('ล้างการค้นหา'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('สแกนบาร์โค้ด'));
    await tester.tap(find.byKey(const ValueKey('sales-bundles')));
    expect(scans, 2);
    expect(bundles, 1);
    await tester.tap(find.byKey(const ValueKey('sales-tab-favorites')));
    await tester.tap(find.byKey(const ValueKey('sales-tab-all')));
    await tester.pumpAndSettle();
    await pref.load();
    expect(pref.value.catalogTab, 'all');
    source.add([_products[1]]);
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductCard), findsOneWidget);
    expect(loads, 1);
    addTearDown(() {
      source.close();
    });
  });

  testWidgets(
      'rotation keeps search and the latest category while a save is pending',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _BlockedDisplayController();
    await controller.load();
    await tester.pumpWidget(MaterialApp(
        home: SaleDisplayScope(
            controller: controller, child: const _Workspace())));
    await tester.pumpAndSettle();
    final catalog = tester.element(find.byType(PosCatalog));
    await tester.tap(find.byKey(const ValueKey('sales-tab-all')));
    await tester.tap(find.byKey(const ValueKey('sales-tab-favorites')));
    await tester.enterText(find.byKey(const ValueKey('sales-search')), '123');
    tester.view.physicalSize = const Size(390, 960);
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(PosCatalog)), same(catalog));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('sales-search')))
            .controller!
            .text,
        '123');
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const ValueKey('sales-tab-favorites')))
            .selected,
        isTrue);
    controller.release.complete();
    await tester.pumpAndSettle();
    final restored = SaleDisplayController('rotation');
    await restored.load();
    expect(restored.value.catalogTab, 'favorites');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed catalog recovers and empty favorites remain actionable',
      (tester) async {
    var attempt = 0;
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: PokpokTheme.light(),
            home: Scaffold(
                body: PosCatalog(
                    loadProducts: () => ++attempt == 1
                        ? Stream.error(StateError('fixture unavailable'))
                        : Stream.value([_products[1]]),
                    onAdd: (_) {},
                    onScan: () {},
                    onChooseBundle: () {})))));
    await tester.pumpAndSettle();
    expect(
        find.text('โหลดสินค้าไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'), findsOneWidget);
    await _capture(tester, boundary, 'catalog-error');
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('ชาไทยเย็น'), findsOneWidget);
    expect(attempt, 2);
    await tester.tap(find.byKey(const ValueKey('sales-tab-favorites')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('ปักหมุดสินค้าได้ที่หน้าสินค้า'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('sales-search')), 'ไม่พบรายการนี้');
    await tester.pumpAndSettle();
    expect(find.text('ไม่พบสินค้าที่ค้นหาในหมวดนี้'), findsOneWidget);
  });

  testWidgets('offline and staff actions respect disabled header state',
      (tester) async {
    var offline = 0, staff = 0;
    Widget app(bool locked) => MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                appBar: posSalesHeader(context,
                    title: 'ขายกลับบ้าน',
                    busy: locked,
                    canOpenOffline: !locked,
                    onOffline: () => offline++,
                    onSwitchStaff: () => staff++))));
    await tester.pumpWidget(app(true));
    await tester.tap(find.byTooltip('เปลี่ยนผู้ใช้'));
    expect(staff, 0);
    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
            .enabled,
        isFalse);
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(false));
    await tester.tap(find.byTooltip('เปลี่ยนผู้ใช้'));
    await tester.tap(find.byTooltip('เพิ่มเติม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ขายออฟไลน์ / บิลค้าง'));
    await tester.pumpAndSettle();
    expect(staff, 1);
    expect(offline, 1);
  });

  testWidgets(
      'settings are secondary and persist without resetting cart; tablet bill actions enforce permissions',
      (tester) async {
    final controller = SaleDisplayController('settings');
    await controller.load();
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: SaleDisplayScope(
            controller: controller, child: const _Workspace())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sale-product-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ตะกร้า 1 หน่วย'), findsOneWidget);
    expect(find.text('รูปภาพสินค้า'), findsNothing);
    await tester.tap(find.text('จัดหน้าขาย'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปุ่มชื่อสินค้า'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เสร็จ'));
    await tester.pumpAndSettle();
    expect(controller.value.mode, SaleDisplayMode.names);
    expect(find.textContaining('ตะกร้า 1 หน่วย'), findsOneWidget);
    await tester.tap(find.textContaining('ตะกร้า 1 หน่วย'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มลูกค้า').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('checkout-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ส่วนลด'));
    await tester.pumpAndSettle();
    expect(find.text('฿60.00'), findsOneWidget);
    expect(find.text('รวม ฿70.00 · ส่วนลด ฿10.00'), findsOneWidget);
  });

  for (final width in [390.0, 768.0, 1440.0, 320.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('chooser and sales journey width=$width text=$scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = SaleDisplayController('layout');
        await controller.load();
        await controller.save(controller.value.withMode(SaleDisplayMode.names));
        final root = GlobalKey();
        final dark = scale == 2;
        await tester.pumpWidget(RepaintBoundary(
            key: root,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: SaleDisplayScope(
                    controller: controller,
                    child: const RestaurantSalesScreen(
                        dineIn: _Tables(), takeaway: _Workspace())))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-chooser-${scale.toInt()}');
        }
        await tester
            .ensureVisible(find.byKey(const ValueKey('sales-channel-2')));
        await tester.tap(find.byKey(const ValueKey('sales-channel-2')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-catalog-${scale.toInt()}');
        }
        // Product cards below the first viewport remain reachable with price
        // and availability intact; large text must not require smaller labels.
        if (width < 500 && scale == 2) {
          await tester.drag(
              find.byType(SaleProductGrid), const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        if (width == 390 && scale == 2) {
          await _capture(tester, root, '390-catalog-scrolled-2');
        }
        expect(find.text('หมด').hitTestable(), findsOneWidget);
        expect(find.text('฿50.00').hitTestable(), findsOneWidget);
        await tester.drag(find.byKey(const ValueKey('sale-product-3')),
            const Offset(0, 1000));
        await tester.pumpAndSettle();
        await tester.tap(find.text('จัดหน้าขาย'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-settings-${scale.toInt()}');
        }
        await tester.tap(find.text('สีปุ่ม'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-colors-${scale.toInt()}');
        }
        // Dismiss the nested color dialog, then the display settings.
        Navigator.of(tester.element(find.byType(AlertDialog).last)).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.text('เสร็จ'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const ValueKey('sales-search')), '123');
        await tester.pumpAndSettle();
        expect(find.textContaining('บาร์โค้ด 123'), findsOneWidget);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-search-${scale.toInt()}');
        }
        await tester.tap(find.byTooltip('ล้างการค้นหา'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sale-product-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('เลือกประเภทการขาย'));
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('sales-channel-1')));
        await tester.tap(find.byKey(const ValueKey('sales-channel-1')));
        await tester.pumpAndSettle();
        expect(find.text('F1').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-dine-in-${scale.toInt()}');
        }
        await tester.tap(find.byTooltip('เลือกประเภทการขาย'));
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const ValueKey('sales-channel-2')));
        await tester.tap(find.byKey(const ValueKey('sales-channel-2')));
        await tester.pumpAndSettle();
        if (width < 900) {
          await tester.tap(find.textContaining('ตะกร้า 1 หน่วย'));
          await tester.pumpAndSettle();
        }
        expect(find.text('฿70.00'), findsWidgets);
        expect(find.text('ขายกลับบ้าน').hitTestable(), findsOneWidget);
        expect(tester.getTopLeft(find.text('ขายกลับบ้าน')).dy,
            greaterThanOrEqualTo(0));
        expect(find.byKey(const ValueKey('checkout-pay')).hitTestable(),
            findsOneWidget);
        expect(find.text('เพิ่มลูกค้า').hitTestable(), findsOneWidget);
        expect(find.byTooltip('เพิ่มจำนวน').hitTestable(), findsOneWidget);
        expect(find.byTooltip('ลบรายการ').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width != 320) {
          await _capture(
              tester, root, '${width.toInt()}-basket-${scale.toInt()}');
        }
        await tester.tap(find.byTooltip('เพิ่มจำนวน'));
        await tester.pumpAndSettle();
        expect(find.text('฿140.00'), findsWidgets);
        await tester.tap(find.byTooltip('ลดจำนวน'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('checkout-pay')));
        await tester.pumpAndSettle();
        if (width < 900) {
          expect(find.textContaining('ตะกร้า 0 หน่วย'), findsOneWidget);
        }
      });
    }
  }
}

class _Tables extends StatelessWidget {
  const _Tables();
  @override
  Widget build(BuildContext context) => TablesScreen(
      loadTables: () => Stream.value([
            RestaurantTable(
                id: 'F1', name: 'F1', createdAt: DateTime(2026, 11, 13)),
          ]),
      loadOpenOrders: () => Stream.value(const []));
}

class _BlockedDisplayController extends SaleDisplayController {
  _BlockedDisplayController() : super('rotation');
  final release = Completer<void>();
  bool _firstSave = true;
  @override
  Future<void> save(SaleDisplaySettings next) async {
    if (_firstSave) {
      _firstSave = false;
      busy = true;
      notifyListeners();
      await release.future;
      busy = false;
    }
    await super.save(next);
  }
}

/// Production layout/catalog/basket/checkout; only data and business callbacks
/// are fixtures. Does not claim to exercise real authentication or payment.
class _Workspace extends StatefulWidget {
  const _Workspace();
  @override
  State<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<_Workspace> {
  final items = <CartItem>[];
  double discount = 0;
  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (v, p) => v + p.subtotal);
    return Scaffold(
        appBar: posSalesHeader(context,
            title: 'ขายกลับบ้าน',
            cashier: 'พนักงานทดสอบชื่อยาวสำหรับตรวจหน้าจอ',
            busy: false,
            canOpenOffline: items.isEmpty,
            onOffline: () {},
            onSwitchStaff: () {}),
        body: PosSalesWorkspace(
            itemCount: items.length,
            total: total - discount,
            catalog: PosCatalog(
                loadProducts: () => Stream.value(_products),
                onAdd: (p) => setState(() => items.add(CartItem(product: p))),
                onScan: () {},
                onChooseBundle: () {}),
            basket: PosBasket(
                itemCount: items.length,
                customerAction: TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('เพิ่มลูกค้า')),
                itemBuilder: (_, i) => CartItemTile(
                    item: items[i],
                    onRemove: () => setState(() => items.removeAt(i)),
                    onQtyChanged: (qty) => setState(() {
                          if (qty <= 0) {
                            items.removeAt(i);
                          } else {
                            items[i] = items[i].copyWith(quantity: qty);
                          }
                        }))),
            checkout: PosCheckoutPanel(
                subtotal: total,
                discount: discount,
                total: total - discount,
                compact: MediaQuery.sizeOf(context).width < 900,
                onDiscount: () => setState(() => discount = 10),
                onCheckout: () => setState(() {
                      items.clear();
                      discount = 0;
                    }),
                onDebt: () {},
                hasItems: items.isNotEmpty,
                canDiscount: true,
                canDebt: true)));
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  // Repaint retained layers before taking consecutive widget-test snapshots.
  // Otherwise an unchanged AppBar can be omitted by the test renderer.
  void repaint(RenderObject object) {
    object.markNeedsPaint();
    object.visitChildren(repaint);
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('.remember/tmp/sales-workspace/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
