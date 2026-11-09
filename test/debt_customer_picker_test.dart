import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/customer.dart';
import 'package:shop_pos/models/debt.dart';
import 'package:shop_pos/services/customer_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/debt_customer_picker.dart';

void main() {
  final customers = [
    Customer(
        id: 'c1',
        name: 'คุณเอ',
        phone: '0811111111',
        createdAt: DateTime(2026, 11, 1)),
    Customer(id: 'c2', name: 'คุณบี', phone: '', createdAt: DateTime(2026)),
  ];
  final debts = [
    Debt(
        id: 'd1',
        customerName: 'ป้าแดง',
        amount: 50,
        createdAt: DateTime(2026, 10, 1),
        saleId: 'd1'),
    Debt(
        id: 'd2',
        customerName: 'คุณเอ',
        amount: 20,
        createdAt: DateTime(2026, 10, 2),
        saleId: 'd2'),
  ];

  Future<List<DebtCustomerChoice?>> open(WidgetTester tester,
      {required List<(String, String)> created, Object? createError}) async {
    final results = <DebtCustomerChoice?>[];
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async => results.add(
                            await DebtCustomerPicker.show(context,
                                customers: Stream.value(customers),
                                debts: Stream.value(debts),
                                create: (name, phone) async {
                          created.add((name, phone));
                          if (createError != null) throw createError;
                          return Customer(
                              id: 'new-$name',
                              name: name,
                              phone: phone,
                              createdAt: DateTime(2026, 11, 8));
                        })),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('search finds customers by name or phone and returns their id',
      (tester) async {
    final created = <(String, String)>[];
    final results = await open(tester, created: created);
    expect(find.text('คุณเอ'), findsOneWidget, reason: 'deduplicated');
    expect(find.text('ป้าแดง'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('debt-customer-search')), '0811');
    await tester.pumpAndSettle();
    expect(find.text('คุณบี'), findsNothing);
    await tester.tap(find.text('คุณเอ'));
    await tester.pumpAndSettle();
    expect(results.single!.customerId, 'c1');
    expect(created, isEmpty);
  });

  testWidgets('an older debt name becomes a customer record when picked',
      (tester) async {
    final created = <(String, String)>[];
    final results = await open(tester, created: created);
    await tester.tap(find.text('ป้าแดง'));
    await tester.pumpAndSettle();
    expect(created, [('ป้าแดง', '')]);
    expect(results.single!.customerId, 'new-ป้าแดง');
  });

  testWidgets('a new customer needs a name and keeps an optional phone',
      (tester) async {
    final created = <(String, String)>[];
    final results = await open(tester, created: created);
    await tester.tap(find.byKey(const ValueKey('debt-customer-add')));
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('debt-customer-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
        find.byKey(const ValueKey('debt-customer-search')), 'ลุงดำ');
    await tester.enterText(
        find.byKey(const ValueKey('debt-customer-phone')), '0822222222');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(created, [('ลุงดำ', '0822222222')]);
    expect(results.single!.name, 'ลุงดำ');
  });

  test('a phone owned by a differently named customer is a conflict', () {
    final owner = customers.first;
    expect(CustomerService.phoneConflict(owner, ' คุณเอ '), isNull);
    expect(CustomerService.phoneConflict(owner, 'ป้าแดง'), contains('คุณเอ'));
  });

  testWidgets('a rejected new customer shows why and records no debt',
      (tester) async {
    final created = <(String, String)>[];
    final results = await open(tester,
        created: created,
        createError: StateError(
            CustomerService.phoneConflict(customers.first, 'ป้าแดง')!));
    await tester.tap(find.byKey(const ValueKey('debt-customer-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('debt-customer-search')), 'ป้าแดง');
    await tester.enterText(
        find.byKey(const ValueKey('debt-customer-phone')), '0811111111');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('debt-customer-save')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('เบอร์นี้เป็นของลูกค้า "คุณเอ"'), findsOneWidget);
    expect(find.textContaining('Bad state'), findsNothing);
    expect(results, isEmpty, reason: 'the dialog stays open');
  });
}
