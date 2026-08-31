/// Thrown by [SaleRepository.createSale] when a line's effective per-unit
/// price — after its own discount and its proportional share of the cart-
/// level discount — falls below that product's minSellingPrice floor.
/// Checked in the repository itself (not just the cart/checkout UI), so it
/// can't be bypassed by a caller that skips client-side validation.
class PriceBelowFloorException implements Exception {
  const PriceBelowFloorException({
    required this.productName,
    required this.effectivePrice,
    required this.minSellingPrice,
  });

  final String productName;
  final double effectivePrice;
  final double minSellingPrice;

  @override
  String toString() =>
      "'$productName' would sell at ${effectivePrice.toStringAsFixed(2)} "
      'after discount, below its minimum selling price of '
      '${minSellingPrice.toStringAsFixed(2)}.';
}
