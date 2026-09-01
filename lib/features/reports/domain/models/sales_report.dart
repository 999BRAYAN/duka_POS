/// One product's slice of [SalesReport.productBreakdown].
class ProductRevenue {
  const ProductRevenue({
    required this.productId,
    required this.productName,
    required this.quantitySold,
    required this.revenue,
  });

  final int productId;
  final String productName;
  final double quantitySold;

  /// Sum of `SaleItems.total` for this product — already net of that
  /// line's own discount, same convention `SaleRepository` relies on
  /// elsewhere.
  final double revenue;
}

/// Sales performance over a DateRange, scoped to completed sales only — a
/// void sale never happened as far as revenue is concerned. See
/// SalesReportRepository.getSalesReport.
class SalesReport {
  const SalesReport({
    required this.totalRevenue,
    required this.saleCount,
    required this.averageSaleValue,
    required this.productBreakdown,
  });

  final double totalRevenue;
  final int saleCount;
  final double averageSaleValue;

  /// Revenue by product, highest first. Empty when [saleCount] is zero.
  final List<ProductRevenue> productBreakdown;
}
