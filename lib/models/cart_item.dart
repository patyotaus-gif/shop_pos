import 'product.dart';
import 'order_modifier.dart';

class CartItem {
  final Product product;
  final int quantity;
  final double discount;
  final List<OrderModifier> modifiers;
  final String? notes;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
    this.modifiers = const [],
    this.notes,
  });

  double get unitPrice =>
      product.effectivePrice +
      modifiers.fold<double>(0, (s, m) => s + m.priceAdjust);
  double get subtotal => (unitPrice * quantity) - discount;

  CartItem copyWith({int? quantity, double? discount}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        discount: discount ?? this.discount,
        modifiers: modifiers,
        notes: notes,
      );
}
