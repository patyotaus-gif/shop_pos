import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/cash_session_status_banner.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

void main() {
  testWidgets('closed-round warning fits small phone and opens round action',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
                body: Align(
                    alignment: Alignment.bottomCenter,
                    child: CashSessionNotice(
                        message:
                            'รอบขายปิดอยู่ · เปิดรอบและยืนยันเงินทอนก่อนขาย',
                        onOpen: () => taps++))))));
    await tester.tap(find.text('เปิดรอบ'));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
