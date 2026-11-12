import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/staff_sales_entry.dart';
import 'package:shop_pos/screens/offline_cash_screen.dart';

void main() {
  for (final example in [
    ('restaurant', 'restaurant', true),
    ('full', 'restaurant', true),
    ('full', 'retail', false),
    ('solo', 'restaurant', false),
  ]) {
    testWidgets('staff selling entry follows shop tier/type $example',
        (tester) async {
      final workspace = Completer<Map<String, dynamic>>();
      var loads = 0;
      Widget app() => MaterialApp(
          home: Scaffold(
              body: StaffSalesEntry(
                  loadWorkspace: () {
                    loads++;
                    return workspace.future;
                  },
                  restaurant: const Text('choose dine-in or takeaway'),
                  retail: const Text('retail catalog'))));
      await tester.pumpWidget(app());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
          tester
              .widget<OfflineEntryButton>(find.byType(OfflineEntryButton))
              .allowPrepare,
          isFalse);
      expect(find.text('retail catalog'), findsNothing);
      workspace.complete({
        'shop': {'tier': example.$1, 'shopType': example.$2}
      });
      await tester.pumpAndSettle();
      expect(
          find.text(
              example.$3 ? 'choose dine-in or takeaway' : 'retail catalog'),
          findsOneWidget);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(loads, 1);
    });
  }

  testWidgets('staff workspace failure blocks wrong entry and can retry',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StaffSalesEntry(
      loadWorkspace: () async {
        if (++attempts == 1) throw StateError('fixture unavailable');
        return {
          'shop': {'tier': 'restaurant', 'shopType': 'restaurant'}
        };
      },
      restaurant: const Text('choose dine-in or takeaway'),
      retail: const Text('retail catalog'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('retail catalog'), findsNothing);
    expect(find.text('choose dine-in or takeaway'), findsNothing);
    expect(find.text('ขายออฟไลน์ / บิลค้าง').hitTestable(), findsOneWidget);
    expect(
        tester
            .widget<OfflineEntryButton>(find.byType(OfflineEntryButton))
            .allowPrepare,
        isFalse);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.text('choose dine-in or takeaway'), findsOneWidget);
    expect(attempts, 2);
  });
}
