import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/screens/sale_receipt_screen.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/screens/tables_screen.dart';
import 'package:shop_pos/widgets/status_badge.dart';

void main() {
  testWidgets(
      'quantity previews immediately, blocks checkout and restores on failed save',
      (tester) async {
    final saving = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: TableOrderView(
          order: TableOrder(
              id: 'o',
              tableId: 't',
              tableName: 'F1',
              openedAt: DateTime.now(),
              items: const [
                TableOrderItem(
                    id: 'rice',
                    productId: 'rice',
                    productName: 'ข้าว',
                    price: 50,
                    quantity: 1),
              ]),
          loadServiceCharge: () async => 0,
          changeQuantity: (orderId, itemId, target, expected) {
            expect(target, 2);
            expect(expected, 1);
            return saving.future;
          },
        ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('table-payment')))
            .onPressed,
        isNull);
    await tester.pump(const Duration(milliseconds: 350));
    saving.completeError(StateError('บันทึกไม่ได้'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('table-payment')))
            .onPressed,
        isNotNull);
  });
  testWidgets('send-to-kitchen mentions gifts only when a gift is pending',
      (tester) async {
    Future<void> pump(List<TableOrderItem> items) async {
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: TableOrderView(
            order: TableOrder(
                id: 'o',
                tableId: 't',
                tableName: '1B',
                openedAt: DateTime.now(),
                items: items),
            loadServiceCharge: () async => 0,
          ))));
      await tester.pumpAndSettle();
    }

    await pump(const [
      TableOrderItem(
          id: 'b', productId: 'b', productName: 'B', price: 5, quantity: 4),
    ]);
    expect(find.text('ส่งครัว (4)'), findsOneWidget);
    expect(find.textContaining('ของแถม'), findsNothing);

    await pump(const [
      TableOrderItem(
          id: 'b', productId: 'b', productName: 'B', price: 5, quantity: 2),
      TableOrderItem(
          id: 'g',
          productId: 'c',
          productName: 'ของแถม: C',
          price: 0,
          quantity: 1,
          isGift: true),
    ]);
    expect(find.text('ส่งครัวพร้อมของแถม (3)'), findsOneWidget);
  });
  testWidgets('table grid separates free, in-use and awaiting-payment tables',
      (tester) async {
    RestaurantTable table(String id, TableStatus status) => RestaurantTable(
        id: id, name: id, status: status, createdAt: DateTime(2026, 11, 8));
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: TablesScreen(
            loadTables: () => Stream.value([
                  table('F1', TableStatus.available),
                  table('1A', TableStatus.occupied),
                  table('1B', TableStatus.occupied),
                ]),
            loadOpenOrders: () => Stream.value([
                  TableOrder(
                      id: 'a',
                      tableId: '1A',
                      tableName: '1A',
                      items: const [],
                      openedAt: DateTime(2026, 11, 8)),
                  TableOrder(
                      id: 'b',
                      tableId: '1B',
                      tableName: '1B',
                      items: const [],
                      openedAt: DateTime(2026, 11, 8),
                      billRequestedAt: DateTime(2026, 11, 8, 12)),
                ]))));
    await tester.pumpAndSettle();
    String badgeOf(String name) => tester
        .widget<StatusBadge>(find.descendant(
            of: find.ancestor(
                of: find.text(name), matching: find.byType(InkWell)),
            matching: find.byType(StatusBadge)))
        .label;
    expect(badgeOf('F1'), 'ว่าง');
    expect(badgeOf('1A'), 'กำลังใช้งาน');
    expect(badgeOf('1B'), 'รอชำระเงิน');
  });
  test('arranged tables come first in their order, the rest by creation', () {
    RestaurantTable t(String id, int day, [int? order]) => RestaurantTable(
        id: id, name: id, createdAt: DateTime(2026, 11, day), sortOrder: order);
    expect(
        RestaurantTable.sorted(
                [t('new', 5), t('1A', 1, 1), t('F1', 3, 0), t('old', 2)])
            .map((t) => t.id),
        ['F1', '1A', 'old', 'new']);
  });
  testWidgets('arranging swaps a dropped table with the target and saves order',
      (tester) async {
    final saved = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: TablesScreen(
            loadTables: () => Stream.value([
                  for (final (i, id) in ['1A', 'F1', '1B'].indexed)
                    RestaurantTable(
                        id: id, name: id, createdAt: DateTime(2026, 11, i + 1)),
                ]),
            loadOpenOrders: () => Stream.value(const []),
            reorderTables: (ids) async => saved.add(ids))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tables-arrange')));
    await tester.pumpAndSettle();
    final from = tester.getCenter(find.text('F1'));
    final to = tester.getCenter(find.text('1A'));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saved, [
      ['F1', '1A', '1B']
    ]);
    expect(tester.getCenter(find.text('F1')).dx,
        lessThan(tester.getCenter(find.text('1A')).dx));
    await tester.tap(find.byKey(const ValueKey('tables-arrange')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ลากโต๊ะ'), findsNothing);
  });
  testWidgets('bill request toggles on the open table and can be undone',
      (tester) async {
    final calls = <bool>[];
    Future<void> pump(DateTime? requestedAt) async {
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: TableOrderView(
            order: TableOrder(
                id: 'o',
                tableId: 't',
                tableName: '1B',
                openedAt: DateTime.now(),
                billRequestedAt: requestedAt,
                items: const [
                  TableOrderItem(
                      id: 'b',
                      productId: 'b',
                      productName: 'B',
                      price: 5,
                      quantity: 1,
                      kitchenStatus: KitchenStatus.sent),
                ]),
            loadServiceCharge: () async => 0,
            setBillRequested: (orderId, requested) async {
              expect(orderId, 'o');
              calls.add(requested);
            },
          ))));
      await tester.pumpAndSettle();
    }

    await pump(null);
    await tester.ensureVisible(find.text('ลูกค้าขอเช็กบิล'));
    await tester.tap(find.text('ลูกค้าขอเช็กบิล'));
    await tester.pumpAndSettle();
    await pump(DateTime(2026, 11, 8, 12));
    await tester.ensureVisible(find.text('ยกเลิกขอเช็กบิล'));
    await tester.tap(find.text('ยกเลิกขอเช็กบิล'));
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });
  testWidgets('kitchen read errors are not presented as an empty kitchen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: KitchenScreen(
            orders: Stream.error(StateError('permission-denied')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดออเดอร์ครัวไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsNothing);
  });
  testWidgets('kitchen shows sent dishes and hides unsent dishes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: KitchenScreen(
            orders: Stream.value([
          TableOrder(
              id: 'order',
              tableId: 't',
              tableName: 'F1',
              openedAt: DateTime.now(),
              items: const [
                TableOrderItem(
                    id: 'a',
                    productId: 'a',
                    productName: 'ข้าวส่งครัวแล้ว',
                    price: 50,
                    quantity: 1,
                    kitchenStatus: KitchenStatus.sent),
                TableOrderItem(
                    id: 'b',
                    productId: 'b',
                    productName: 'ยังไม่ได้ส่ง',
                    price: 50,
                    quantity: 1),
              ])
        ]))));
    await tester.pumpAndSettle();
    expect(find.text('ข้าวส่งครัวแล้ว'), findsOneWidget);
    expect(find.text('ยังไม่ได้ส่ง'), findsNothing);
  });
  testWidgets(
      'receipt loading failure keeps payment success and retries only receipt',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: SaleReceiptScreen(loadSale: () async {
          attempts++;
          throw StateError('offline');
        })));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกการขายสำเร็จ'), findsOneWidget);
    expect(find.textContaining('ไม่ต้องรับเงินซ้ำ'), findsOneWidget);
    await tester.tap(find.text('ลองโหลดใบเสร็จใหม่'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
