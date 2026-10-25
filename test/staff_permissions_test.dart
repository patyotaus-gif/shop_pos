import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/staff_member.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/staff_screen.dart';
import 'package:shop_pos/services/staff_access_service.dart';

void main() {
  test(
      'legacy positions and explicit individual permissions deserialize separately',
      () {
    final old =
        StaffMember.fromFirestore({'name': 'A', 'role': 'cashier'}, 'a');
    expect(old.role, StaffRole.cashier);
    expect(old.permissions, isEmpty);
    final cook = StaffMember.fromFirestore({
      'name': 'B',
      'role': 'cashier',
      'position': 'kitchen',
      'permissions': {'discount': false, 'cancel': true}
    }, 'b');
    expect(cook.role, StaffRole.kitchen);
    expect(cook.permissions['cancel'], true);
    expect(cook.permissions['discount'], false);
    expect(cook.copyWith(name: 'New').role, StaffRole.kitchen);
  });
  test('nested callable timestamps remain usable by table and kitchen models',
      () {
    final data = StaffAccessService.firestoreDates({
      'tableId': 't',
      'tableName': 'T',
      'openedAt': '2026-10-26T08:00:00Z',
      'items': [
        {
          'id': 'i',
          'productName': 'Tea',
          'price': 20,
          'quantity': 1,
          'kitchenStatus': 'sent',
          'sentToKitchenAt': '2026-10-26T08:01:00Z'
        }
      ]
    });
    expect(data['openedAt'], isA<Timestamp>());
    final order = TableOrder.fromFirestore(data, 'o');
    expect(order.items.single.sentToKitchenAt?.toUtc(),
        DateTime.utc(2026, 10, 26, 8, 1));
    expect(order.items.single.costPrice, 0);
  });
  for (final width in [320.0, 800.0]) {
    testWidgets(
        'staff form scrolls and keeps permissions when changing position at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data: MediaQueryData(
                      size: Size(width, 700),
                      textScaler: const TextScaler.linear(1.4),
                      padding: const EdgeInsets.only(bottom: 24)),
                  child: StaffMemberForm(
                      existing: StaffMember(
                          id: 's',
                          name: 'Cashier',
                          pin: '',
                          createdAt: DateTime(2026),
                          permissions: const {'cancel': true}))))));
      expect(tester.takeException(), isNull);
      await tester
          .ensureVisible(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<StaffRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ครัว').last);
      await tester.pumpAndSettle();
      expect(find.text('ครัว'), findsOneWidget);
      final cancel = find.widgetWithText(SwitchListTile, 'ยกเลิกบิล');
      await tester.ensureVisible(cancel);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(cancel).value, true);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();
      expect(
          tester.getBottomRight(find.widgetWithText(FilledButton, 'บันทึก')).dy,
          lessThanOrEqualTo(676));
      expect(tester.takeException(), isNull);
    });
  }
}
