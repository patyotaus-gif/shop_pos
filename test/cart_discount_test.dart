import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/product.dart';

void main() {
  const product =
      Product(id: 'chips', name: 'เลย์', barcode: '', price: 20, stock: 20);

  test('clearing the discounted basket does not discount the next sale', () {
    final cart = [const CartItem(product: product, quantity: 2)];
    var discount = 5.0;
    expect(cart.single.subtotal - discount, 35);
    cart.clear();
    discount = cartDiscountAfterEdit(cart, discount);
    expect(discount, 0);
    cart.add(const CartItem(product: product));
    expect(cart.single.subtotal - discount, 20);
  });

  test('reducing quantity caps the discount without a negative payable', () {
    final cart = [const CartItem(product: product, quantity: 2)];
    var discount = 30.0;
    cart[0] = cart[0].copyWith(quantity: 1);
    discount = cartDiscountAfterEdit(cart, discount);
    expect(discount, 20);
    expect(cart.single.subtotal - discount, 0);
    cart[0] = cart[0].copyWith(quantity: 2);
    expect(cart.single.subtotal - discount, 20);
  });

  test('removing a line retains an affordable discount, including fractions',
      () {
    final cart = [
      const CartItem(product: product, quantity: 0.125),
      const CartItem(product: product),
    ];
    cart.removeLast();
    expect(cartDiscountAfterEdit(cart, 1.25), 1.25);
    expect(cartDiscountAfterEdit(cart, 5), 2.5);
  });
}
