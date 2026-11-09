import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/profit_summary.dart';

void main() {
  Future<String> render(WidgetTester tester, double? price, double? cost,
      {bool fromRecipe = false}) async {
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: ProfitSummary(
                price: price, cost: cost, fromRecipe: fromRecipe))));
    return tester
        .widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('profit-summary')),
            matching: find.byType(Text)))
        .data!;
  }

  testWidgets('shows recipe cost, baht profit and margin of the price',
      (tester) async {
    // Orange Americano: coffee ฿12 + orange juice ฿10 + cup ฿5 = ฿27.
    expect(await render(tester, 65, 27, fromRecipe: true),
        'ต้นทุนตามสูตร ฿27.00 · กำไร ฿38.00 (58.5% ของราคาขาย)');
    expect(await render(tester, 20, 25),
        'ต้นทุน ฿25.00 · กำไร ฿-5.00 (-25.0% ของราคาขาย)');
  });

  testWidgets('asks for the missing number instead of showing fake profit',
      (tester) async {
    expect(await render(tester, null, 10), 'ใส่ราคาขายเพื่อดูกำไร');
    expect(await render(tester, 50, 0), 'ใส่ราคาต้นทุนเพื่อดูกำไร');
    expect(await render(tester, 50, 0, fromRecipe: true),
        'เพิ่มวัตถุดิบในสูตรเพื่อดูต้นทุนและกำไร');
  });
}
