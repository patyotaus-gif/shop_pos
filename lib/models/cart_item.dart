import 'product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final double discount;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
  });

  double get subtotal => (product.price * quantity) - discount;

  CartItem copyWith({int? quantity, double? discount}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        discount: discount ?? this.discount,
      );
}
