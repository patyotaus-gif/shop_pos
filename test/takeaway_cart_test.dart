import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/order_modifier.dart';
import 'package:shop_pos/models/sale.dart';

void main() {
  test(
      'takeaway modifiers affect totals and survive quantity changes and sale snapshots',
      () {
    const product =
        Product(id: 'rice', name: 'ข้าว', barcode: '1', price: 50, stock: 10);
    const egg = OrderModifier(
        groupId: 'extras',
        groupName: 'เพิ่ม',
        optionId: 'egg',
        optionName: 'ไข่',
        priceAdjust: 10,
        costAdjust: 3);
    const cart = CartItem(
        product: product, quantity: 2, modifiers: [egg], notes: 'ไม่เผ็ด');
    expect(cart.unitPrice, 60);
    expect(cart.subtotal, 120);
    expect(cart.copyWith(quantity: 3).subtotal, 180);
    expect(cart.copyWith(quantity: 3).notes, 'ไม่เผ็ด');
    final sale = SaleItem(
        productId: product.id,
        productName: product.name,
        price: product.price,
        quantity: cart.quantity,
        subtotal: cart.subtotal,
        modifiers: cart.modifiers,
        notes: cart.notes);
    final restored = SaleItem.fromMap(sale.toMap());
    expect(restored.subtotal, 120);
    expect(restored.modifiers.single.costAdjust, 3);
    expect(restored.notes, 'ไม่เผ็ด');
    expect(modifiersEqual(cart.modifiers, []), isFalse);
  });
}
