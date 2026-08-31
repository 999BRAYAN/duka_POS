/// One line in the in-progress sale cart. [name] and [price] are snapshotted
/// at add-to-cart time, so a line already in the cart doesn't silently
/// change if the product's own name/price is edited elsewhere while the
/// cart is open. Deliberately carries no cost field — unlike price, cost is
/// snapshotted at checkout (read fresh from the product then), not here.
class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  final int productId;
  final String name;
  final double price;
  final double quantity;

  double get lineTotal => price * quantity;

  CartLine copyWith({double? quantity}) {
    return CartLine(
      productId: productId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CartLine &&
      other.productId == productId &&
      other.name == name &&
      other.price == price &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(productId, name, price, quantity);

  @override
  String toString() =>
      'CartLine(productId: $productId, name: $name, price: $price, quantity: $quantity)';
}
