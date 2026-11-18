import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/widgets/report_stock_card.dart';

void main() {
  testWidgets('stock opens on demand and separates recipes and unpriced stock',
      (tester) async {
    var reads = 0;
    const products = [
      Product(
          id: 'a',
          name: 'ข้าว',
          barcode: '',
          price: 50,
          costPrice: 20,
          stock: 2),
      Product(id: 'b', name: 'น้ำ', barcode: '', price: 10, stock: 3),
      Product(id: 'c', name: 'ชา', barcode: '', price: 50, stock: 0),
      Product(
          id: 'd',
          name: 'อาหารตามสูตร',
          barcode: '',
          price: 50,
          stock: 0,
          stockMode: 'recipe'),
    ];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(
      children: [
        ReportStockCard(watchProducts: () {
          reads++;
          return Stream.value(products);
        })
      ],
    ))));
    expect(reads, 0);
    await tester.tap(find.text('สินค้าคงเหลือปัจจุบัน'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(
        find.textContaining('หมด 1 รายการ · ใกล้หมด 2 รายการ'), findsOneWidget);
    expect(find.textContaining('฿40.00'), findsOneWidget);
    expect(find.textContaining('ยังไม่รวม 1 รายการ'), findsOneWidget);
    expect(find.text('อาหารตามสูตร'), findsNothing);
  });
}
