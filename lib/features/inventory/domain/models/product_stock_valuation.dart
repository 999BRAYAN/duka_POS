/// One row of [StockValuationRepository.watchStockValuation] — computed
/// live from [Product] and [StockMovement], never a stored value.
class ProductStockValuation {
  const ProductStockValuation({
    required this.productId,
    required this.uuid,
    required this.name,
    required this.stock,
    required this.reorderLevel,
    required this.averageCost,
    required this.stockValue,
    required this.isLowStock,
  });

  final int productId;
  final String uuid;
  final String name;

  final double stock;
  final double reorderLevel;

  /// Weighted average of `unitCost` across this product's PURCHASE
  /// movements (`SUM(quantity * unitCost) / SUM(quantity)`), falling back
  /// to `Product.costPrice` when it has no purchase history yet.
  final double averageCost;

  /// `stock * averageCost`.
  final double stockValue;

  /// `stock <= reorderLevel`.
  final bool isLowStock;
}
