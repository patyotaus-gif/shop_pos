import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';

Product _p({
  double price = 20,
  double? salePrice,
  DateTime? saleUntil,
}) =>
    Product(
      id: 'p1',
      name: 'มาม่า',
      barcode: '885',
      price: price,
      stock: 10,
      salePrice: salePrice,
      saleUntil: saleUntil,
    );

void main() {
  group('Product promo', () {
    test('active sale: isOnSale, effectivePrice, discountPercent', () {
      final p = _p(price: 20, salePrice: 10);
      expect(p.isOnSale, isTrue);
      expect(p.effectivePrice, 10);
      expect(p.discountPercent, 50);
    });

    test('expired saleUntil → no sale', () {
      final p = _p(
        price: 20,
        salePrice: 10,
        saleUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(p.isOnSale, isFalse);
      expect(p.effectivePrice, 20);
      expect(p.discountPercent, 0);
    });

    test('future saleUntil → sale active', () {
      final p = _p(
        price: 20,
        salePrice: 15,
        saleUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(p.isOnSale, isTrue);
      expect(p.discountPercent, 25);
    });

    test('salePrice >= price → no sale', () {
      expect(_p(price: 20, salePrice: 20).isOnSale, isFalse);
      expect(_p(price: 20, salePrice: 25).discountPercent, 0);
    });

    test('tiny discount rounds to 0% → badge hidden', () {
      final p = _p(price: 1000, salePrice: 996);
      expect(p.isOnSale, isTrue); // still charged the sale price
      expect(p.discountPercent, 0); // but no badge
    });
  });
}
