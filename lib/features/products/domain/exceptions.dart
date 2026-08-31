/// Thrown by [ProductService] when a product is saved with a minimum
/// selling price below its cost price and the caller hasn't confirmed the
/// override. Callers (UI) are expected to catch this, ask the user to
/// confirm, and retry with the override set rather than silently ignoring
/// it.
class PriceBelowCostException implements Exception {
  const PriceBelowCostException({
    required this.costPrice,
    required this.minSellingPrice,
  });

  final double costPrice;
  final double minSellingPrice;

  @override
  String toString() =>
      'Minimum selling price ($minSellingPrice) is below cost price '
      '($costPrice).';
}
