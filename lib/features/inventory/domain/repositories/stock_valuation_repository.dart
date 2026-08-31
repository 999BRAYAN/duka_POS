import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';

/// Per-product stock valuation, computed live on every emission rather than
/// stored anywhere — nothing here can drift out of sync with
/// Products/StockMovements the way a cached column could. Built as its own
/// query so dashboard and reporting features can watch it directly instead
/// of each recomputing average cost / low-stock status themselves.
abstract interface class StockValuationRepository {
  Stream<List<ProductStockValuation>> watchStockValuation();
}
