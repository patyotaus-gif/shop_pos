import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/staff_inventory_screen.dart';
import 'package:shop_pos/services/staff_inventory_api.dart';

Map<String, dynamic> product() => {
      'id': 'p',
      'name': 'บราวนี่',
      'barcode': '885001',
      'sku': 'BR-1',
      'price': 35,
      'stock': 10,
      'stockRevision': 2,
      'unit': 'ชิ้น',
      'isWeighed': false,
      'trackLots': false,
      'stockMode': 'own',
      'stockLots': <Map>[],
      'reserved': 2,
      'available': 8,
    };

class FakeInventoryApi extends StaffInventoryApi {
  FakeInventoryApi(this.grants);
  final Set<String> grants;
  Map<String, dynamic>? saved;
  final calls = <Map<String, dynamic>>[];
  String? failure;
  @override
  bool can(String permission) => grants.contains(permission);
  @override
  Future<Map<String, dynamic>?> pending(String productId) async => saved;
  @override
  Future<void> savePending(
      String productId, Map<String, dynamic> request) async {
    saved = Map.from(request);
  }

  @override
  Future<void> clearPending(String productId) async {
    saved = null;
  }

  @override
  Future<Map<String, dynamic>> call(
      String action, Map<String, dynamic> data) async {
    calls.add({'action': action, ...data});
    if (action == 'inventoryProduct') return {'record': product()};
    if (action == 'inventoryProducts') {
      return {
        'records': [product()],
        'nextCursor': null
      };
    }
    if (action == 'stockHistory') {
      return {
        'records': [
          {
            'id': data['cursor'] ?? 'h1',
            'kind': data['cursor'] == null ? 'receive' : 'waste',
            'delta': 2,
            'before': 8,
            'after': 10,
            'unit': 'ชิ้น',
            'createdAt': '2026-01-02T08:00:00Z',
            'actorName': 'แคชเชียร์หนึ่ง',
            'reason': 'รับสินค้า',
            'documentNumber': 'PO-1',
            'referenceId': '',
            'lots': []
          },
        ],
        'nextCursor': data['cursor'] == null ? 'h2' : null
      };
    }
    if (failure != null) {
      throw FirebaseFunctionsException(
          code: failure!, message: 'test rejection');
    }
    return {'success': true};
  }
}

Future<void> host(WidgetTester tester, Widget child,
    {double width = 320}) async {
  tester.view.physicalSize = Size(width, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
    data: MediaQueryData(
        size: Size(width, 740),
        textScaler: const TextScaler.linear(1.4),
        padding: const EdgeInsets.only(bottom: 24)),
    child: child,
  )));
  await tester.pumpAndSettle();
}

Future<void> openDialog(WidgetTester tester, FakeInventoryApi api,
    {String action = 'stockReceive', Map<String, dynamic>? p}) async {
  await host(
      tester,
      Scaffold(
          body: Builder(
              builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => StaffStockAdjustmentDialog(
                            product: p ?? product(), action: action, api: api)),
                    child: const Text('เปิด'),
                  ))));
  await tester.tap(find.text('เปิด'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone detail shows only authorized actions and product identity',
      (tester) async {
    final api = FakeInventoryApi({'stockReceive'});
    await host(tester, StaffInventoryDetailScreen(productId: 'p', api: api));
    expect(find.text('รับสินค้าเข้า'), findsOneWidget);
    expect(find.text('ตัดของเสีย / ชำรุด'), findsNothing);
    expect(find.text('ตรวจนับ'), findsNothing);
    expect(find.text('ประวัติสต๊อก'), findsNothing);
    expect(find.textContaining('885001'), findsOneWidget);
    expect(find.textContaining('ราคาขาย ฿35.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search submits exact barcode mode, not a name prefix',
      (tester) async {
    final api = FakeInventoryApi({'stockHistory'});
    await host(tester, StaffInventoryScreen(api: api));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บาร์โค้ด').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '885001');
    await tester.tap(find.byTooltip('ค้นหา'));
    await tester.pumpAndSettle();
    expect(api.calls.last['mode'], 'barcode');
    expect(api.calls.last['search'], '885001');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'receipt retry survives dialog reopening and reuses exact request',
      (tester) async {
    final api = FakeInventoryApi({'stockReceive'})..failure = 'unavailable';
    await openDialog(tester, api);
    expect(find.text('ต้นทุนรวมที่รับเข้า (บาท)'), findsNothing);
    final quantity = find.widgetWithText(TextField, 'จำนวนรับเข้า (ชิ้น)');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '3');
    final reason = find.widgetWithText(TextField, 'เหตุผล');
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'รับจากผู้จำหน่าย');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    final first = Map<String, dynamic>.from(api.calls.last);
    expect(first['quantity'], 3);
    expect(first['expectedRevision'], 2);
    expect(api.saved, isNotNull);
    expect(find.textContaining('รายการรอยืนยัน:'), findsOneWidget);
    await tester.tap(find.text('ปิด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();
    api.failure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'ตรวจผล / ลองใหม่'));
    await tester.pumpAndSettle();
    expect(api.calls.last, first);
    expect(api.saved, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rejected stale count can be closed and refreshed without stuck pending request',
      (tester) async {
    final api = FakeInventoryApi({'stock'})..failure = 'failed-precondition';
    await openDialog(tester, api, action: 'stockCount');
    final quantity = find.widgetWithText(TextField, 'จำนวนที่นับได้ (ชิ้น)');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '0');
    final reason = find.widgetWithText(TextField, 'เหตุผล');
    await tester.ensureVisible(reason);
    await tester.enterText(reason, 'ตรวจนับหมด');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(api.calls.last['quantity'], 0);
    expect(api.saved, isNull);
    expect(find.widgetWithText(FilledButton, 'บันทึก'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history appends the next page and displays actor and balances',
      (tester) async {
    final api = FakeInventoryApi({'stockHistory'});
    await host(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                child: StaffStockHistory(productId: 'p', api: api))));
    expect(find.textContaining('ผู้ทำรายการ: แคชเชียร์หนึ่ง'), findsOneWidget);
    expect(find.textContaining('ก่อน 8 → หลัง 10'), findsOneWidget);
    await tester.ensureVisible(find.text('โหลดประวัติเพิ่มเติม'));
    await tester.tap(find.text('โหลดประวัติเพิ่มเติม'));
    await tester.pumpAndSettle();
    expect(api.calls.last['cursor'], 'h2');
    expect(
        find.textContaining('ผู้ทำรายการ: แคชเชียร์หนึ่ง'), findsNWidgets(2));
    expect(find.text('โหลดประวัติเพิ่มเติม'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
