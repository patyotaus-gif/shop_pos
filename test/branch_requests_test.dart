import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/branch_requests_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

Widget page(Widget home, GlobalKey key, {bool dark = false}) => RepaintBoundary(
    key: key,
    child: MaterialApp(
        initialRoute: '/branches',
        routes: {'/': (_) => const Scaffold(), '/branches': (_) => home},
        theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('th'),
        supportedLocales: const [Locale('th')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates));

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final folder = Platform.environment['POKPOK_BRANCH_CAPTURES'];
  if (folder == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(folder).create(recursive: true);
    await File('$folder/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

const row = {
  'name': 'สาขาตลาดเช้า',
  'shopName': 'ครัวริมสวน',
  'address': 'ตลาดเช้า เชียงใหม่',
  'note': '',
  'reason': '',
  'ownerEmail': 'owner@example.test',
  'termsAtSubmission': {'planStatus': 'trial', 'endsAtMs': 1796976000000},
  'id': 'demo',
  'revision': 1,
  'status': 'pending'
};
Map<String, dynamic> shop(List<Map> items) => {
      'shopName': 'ครัวริมสวน',
      'planStatus': 'trial',
      'endsAtMs': DateTime(2026, 12, 11).millisecondsSinceEpoch,
      'items': items
    };

Future<void> press(WidgetTester tester, String text) async {
  final button = find.text(text).last;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    for (final weight in ['Regular', 'SemiBold']) {
      await (FontLoader(PokpokTheme.fontFamily)
            ..addFont(
                rootBundle.load('assets/fonts/IBMPlexSansThai-$weight.ttf')))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  for (final width in [320.0, 390.0, 768.0, 1440.0]) {
    testWidgets('branch form and owner history at $width', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, width > 700 ? 850 : 780);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final items = <Map>[];
      final view = BranchRequestsScreen.owner(
          shopId: 'shop',
          call: (name, data) async {
            expect(name, 'merchantBranchRequests');
            expect(data['shopId'], 'shop');
            if (data['action'] == 'submit') {
              expect(data['revision'], 0);
              expect(data['name'], row['name']);
              expect(data['address'], row['address']);
              items.add(row);
              return {'id': 'demo'};
            }
            return shop(items);
          });
      await tester.pumpWidget(page(view, key, dark: width == 320));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('สาขาใหม่ใช้สิทธิ์ทดลองเดิมถึง'), findsOneWidget);
      await capture(tester, key, 'form-${width.toInt()}');
      await press(tester, 'ส่งคำขอเพิ่มสาขา');
      expect(find.text('กรุณากรอกช่องนี้'), findsNWidgets(2));
      await tester.enterText(
          find.byType(TextFormField).at(0), row['name'] as String);
      await tester.enterText(
          find.byType(TextFormField).at(1), row['address'] as String);
      await press(tester, 'ส่งคำขอเพิ่มสาขา');
      expect(find.text('รอพิจารณา'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await capture(tester, key, 'status-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('owner retries load and responds to a request for information',
      (tester) async {
    var reads = 0, revision = 1;
    final key = GlobalKey();
    final view = BranchRequestsScreen.owner(
        shopId: 'shop',
        call: (name, data) async {
          if (data['action'] == 'list') {
            if (++reads == 1) throw StateError('โหลดข้อมูลไม่สำเร็จ');
            return shop([
              {
                ...row,
                'status': revision == 1 ? 'moreInfo' : 'pending',
                'reason': revision == 1 ? 'ขอเลขที่บ้าน' : ''
              }
            ]);
          }
          expect(data['revision'], 1);
          expect(data['address'], 'เลขที่ 12 เชียงใหม่');
          revision++;
          return {'id': 'demo'};
        });
    await tester.pumpWidget(page(view, key));
    await tester.pumpAndSettle();
    await press(tester, 'ลองอีกครั้ง');
    await press(tester, 'ส่งข้อมูลเพิ่มเติม');
    expect(find.textContaining('ขอเลขที่บ้าน'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).at(1), 'เลขที่ 12 เชียงใหม่');
    await press(tester, 'ส่งคำขอเพิ่มสาขา');
    expect(find.text('รอพิจารณา'), findsOneWidget);
  });

  testWidgets(
      'founder sees the shop, records a reason, and removes the reviewed request from the queue',
      (tester) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 780);
    addTearDown(tester.view.reset);
    var decided = false;
    final view = BranchRequestsScreen.admin(call: (name, data) async {
      expect(name, 'adminBranchRequests');
      if (data['action'] == 'list') {
        return {
          'items': [if (!decided) row]
        };
      }
      expect(data, {
        'action': 'approved',
        'reason': 'ตรวจสอบแล้ว',
        'revision': 1,
        'id': 'demo'
      });
      decided = true;
      return {'id': 'demo'};
    });
    await tester.pumpWidget(page(view, key));
    await tester.pumpAndSettle();
    await capture(tester, key, 'queue-390');
    await press(tester, 'พิจารณาคำขอ');
    await capture(tester, key, 'review-390');
    await press(tester, 'บันทึกผลพิจารณา');
    expect(find.text('กรุณาเลือกผลพิจารณา'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await press(tester, 'อนุมัติเพิ่มสาขา');
    await tester.enterText(find.byType(TextFormField), 'ตรวจสอบแล้ว');
    await press(tester, 'บันทึกผลพิจารณา');
    expect(find.text('ไม่มีคำขอที่รอพิจารณา'), findsOneWidget);
  });
}
