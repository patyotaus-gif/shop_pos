import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/screens/bundles_screen.dart';
import 'package:shop_pos/screens/buy_get_screen.dart';
import 'package:shop_pos/screens/coupons_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/promotion_form.dart';

const tea = Product(
    id: 'tea',
    name: 'ชาเขียวมัทฉะสูตรเข้มข้นหวานน้อย',
    barcode: '',
    price: 50,
    stock: 20);
const cake = Product(
    id: 'cake', name: 'เค้กช็อกโกแลต', barcode: '', price: 30, stock: 20);

Finder input(String label) => find.descendant(
    of: find.widgetWithText(PromotionField, label),
    matching: find.byType(TextFormField));

void main() {
  setUpAll(() async {
    final font = FontLoader(PokpokTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  // Real editors/theme/font; only persistence is replaced. No customer data.
  for (final kind in ['bundle', 'coupon', 'gift']) {
    for (final width in [320.0, 390.0, 768.0, 1440.0]) {
      for (final dark in [false, true]) {
        testWidgets(
            '$kind $width dark=$dark labels, errors, keyboard and summary',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          Map<String, dynamic>? saved;
          Future<void> save(Map<String, dynamic> data) async => saved = data;
          final Widget editor = switch (kind) {
            'bundle' => BundleEditor(
                products: const [tea, cake],
                onSave: save,
                initial: {
                  'id': 'preview',
                  'name': 'ชุดชาและเค้ก',
                  'priceMinor': 7000,
                  'maxSets': 2,
                  'endsAt': Timestamp.fromDate(
                      DateTime.now().add(const Duration(days: 5))),
                  'components': [
                    {'productId': 'tea', 'quantity': 1},
                    {'productId': 'cake', 'quantity': 1},
                  ],
                }),
            'gift' => BuyGetEditor(
                product: tea, products: const [tea, cake], onSave: save),
            _ => CouponEditor(onSave: save),
          };
          final capture = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: MaterialApp(
                theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(1.5)),
                    child: child!),
                home: Scaffold(
                    body: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => showDialog(
                                context: context, builder: (_) => editor),
                            child: const Text('open')))),
              )));
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();

          if (kind != 'coupon') {
            final name = find
                .descendant(
                    of: find.byType(DropdownButtonFormField<String>).first,
                    matching: find.text(tea.name))
                .first;
            final paragraph = tester.renderObject<RenderParagraph>(name);
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
            )..layout(maxWidth: paragraph.size.width);
            expect(paragraph.size.height,
                greaterThanOrEqualTo(painter.height - 0.1),
                reason: 'Selected product name must remain fully readable');
            painter.dispose();
          }

          // Measure actual label/input geometry, not just absence of exceptions.
          for (final field in find.byType(PromotionField).evaluate()) {
            final scope = find.byWidget(field.widget);
            final label = find
                .descendant(
                    of: scope,
                    matching: find.text((field.widget as PromotionField).label))
                .first;
            final decoration = find
                .descendant(of: scope, matching: find.byType(InputDecorator))
                .first;
            expect(tester.getRect(label).bottom + 7,
                lessThanOrEqualTo(tester.getRect(decoration).top));
            expect(tester.getRect(decoration).left, greaterThanOrEqualTo(0));
            expect(tester.getRect(decoration).right, lessThanOrEqualTo(width));
          }

          if (kind == 'coupon') {
            await tester.enterText(input('โค้ด เช่น WELCOME10'), 'SAVE10');
            await tester.ensureVisible(input('ส่วนลด 1–99%'));
            await tester.enterText(input('ส่วนลด 1–99%'), '10');
            await tester.pumpAndSettle();
            expect(find.text('โค้ด SAVE10 · ลด 10%'), findsOneWidget);
            expect(
                find.text(
                    'ใช้ได้รวม 100 สิทธิ์ทั้งร้าน ไม่ใช่จำนวนสิทธิ์ต่อคน'),
                findsOneWidget);
          } else if (kind == 'bundle') {
            expect(
                find.text('ราคาชุด ฿70.00 · ลด ฿10.00 ต่อชุด'), findsOneWidget);
            await tester.ensureVisible(input('ราคาชุด (บาท)'));
            await tester.enterText(input('ราคาชุด (บาท)'), '65.50');
            await tester.pumpAndSettle();
            expect(
                find.text('ราคาชุด ฿65.50 · ลด ฿14.50 ต่อชุด'), findsOneWidget);
            expect(
                find.text('ราคาชุด ฿70.00 · ลด ฿10.00 ต่อชุด'), findsNothing);
          } else {
            expect(find.text('สูงสุด 1 ชุดต่อออเดอร์ · แถมไม่เกิน 1 ชิ้น'),
                findsOneWidget);
          }

          final action = find.text(switch (kind) {
            'bundle' => 'บันทึกชุด',
            'coupon' => 'สร้างโค้ด',
            _ => 'บันทึก'
          });
          // Error stays inside the form and does not write anything.
          final invalid = kind == 'bundle'
              ? input('จำนวนชุดสูงสุดต่อบิล')
              : kind == 'coupon'
                  ? input('จำนวนสิทธิ์รวมทั้งร้าน')
                  : input('จำนวนชุดสูงสุดต่อออเดอร์');
          await tester.ensureVisible(invalid);
          await tester.enterText(invalid, '0');
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(saved, isNull);
          expect(find.byType(PromotionSummary), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(invalid);
          await tester.enterText(invalid, '2');
          await tester.pumpAndSettle();
          expect(find.byType(PromotionSummary), findsOneWidget);

          // Save remains visible and operable above a simulated software keyboard.
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          expect(tester.getRect(action).bottom, lessThan(600));
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();

          if (Platform.environment['PROMOTION_CAPTURES'] == '1') {
            for (final section in ['fields', 'summary']) {
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.ensureVisible(section == 'fields'
                  ? find.byType(PromotionField).first
                  : find.text('สรุปก่อนบันทึก'));
              await tester.pumpAndSettle();
              await tester.runAsync(() async {
                final image = await (capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                final dir = Directory('.remember/tmp/promotion-preview')
                  ..createSync(recursive: true);
                await File(
                        '${dir.path}/$kind-${width.toInt()}-${dark ? 'dark' : 'light'}-$section.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(saved, isNotNull);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
