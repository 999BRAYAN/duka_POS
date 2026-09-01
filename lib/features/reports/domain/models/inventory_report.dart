import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';

/// One StockMovements.type's net quantity change within the report's
/// DateRange. Keeps the signed-delta convention
/// StockMovementRepository.recordMovement already writes (negative for a
/// SALE, positive for a PURCHASE/RETURN, either sign for an ADJUSTMENT) —
/// this is a straight SUM(quantity), not an absolute value, so it reads
/// exactly like the underlying ledger does.
class MovementTypeSummary {
  const MovementTypeSummary({required this.type, required this.totalQuantity});

  final String type;
  final double totalQuantity;
}

/// Current stock levels alongside what actually moved — received, sold,
/// returned, adjusted — during one DateRange.
class InventoryReport {
  const InventoryReport({required this.stockLevels, required this.movementSummary});

  /// Every active product's current stock and stock × averageCost —
  /// StockValuationRepository's existing view, reused as-is rather than
  /// recomputed here. Not scoped to the report's DateRange: this is a
  /// snapshot of stock right now, not a historical figure.
  final List<ProductStockValuation> stockLevels;

  /// StockMovements.quantity summed by type, scoped to the report's
  /// DateRange.
  final List<MovementTypeSummary> movementSummary;
}
