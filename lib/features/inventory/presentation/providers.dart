import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/providers.dart';
import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stockValuationStreamProvider = StreamProvider<List<ProductStockValuation>>((ref) {
  return ref.watch(stockValuationRepositoryProvider).watchStockValuation();
});

/// Recent stock movements of every kind. The adjustments screen filters this
/// down to ADJUSTMENT rows rather than querying separately — the audit trail
/// is one table, and reading it whole keeps that visible.
final recentMovementsProvider = StreamProvider<List<StockMovement>>((ref) {
  return ref.watch(stockMovementRepositoryProvider).watchRecentMovements(limit: 100);
});
