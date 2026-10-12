import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/online_payment_readiness.dart';

void main() {
  for (final width in [320.0, 820.0]) {
    testWidgets('payment readiness stays readable at $width with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: OnlinePaymentReadiness(),
            ),
          ),
        ),
      ));
      expect(find.text('บัตรเครดิต / เดบิต'), findsOneWidget);
      expect(find.text('TrueMoney'), findsOneWidget);
      expect(find.text('รอเปิดบริการ • ยังรับชำระไม่ได้'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
