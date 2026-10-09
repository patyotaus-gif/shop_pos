import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/payment_sheet.dart';

void main() {
  testWidgets(
      'branded payment stays usable at phone/tablet widths and large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 768.0, 1280.0]) {
      for (final dark in [false, true]) {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 1000);
        PaymentResult? result;
        await tester.pumpWidget(MaterialApp(
          theme: dark ? PokpokTheme.dark() : PokpokTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
              body: Builder(
                  builder: (context) => FilledButton(
                        onPressed: () async {
                          result = await showPaymentSheet(context, total: 135);
                        },
                        child: const Text('รับเงิน'),
                      ))),
        ));
        await tester.tap(find.text('รับเงิน'));
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(DraggableScrollableSheet)).width,
            lessThanOrEqualTo(560));
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField).first, '200');
        await tester.pumpAndSettle();
        expect(find.text('฿65.00'), findsOneWidget);
        final confirm = find.text('ยืนยันการชำระเงิน');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(result?.paid, 200);
        expect(result?.method, PaymentMethod.cash);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
