import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_valuation_repository.dart';

// Average cost is the weighted average unit cost across a product's
// PURCHASE movements only — not RETURN, whose unitCost is copied from
// Product.costPrice at return time rather than a real amount paid to a
// supplier, and would skew the average if included. A product with no
// purchase history yet falls back to Product.costPrice.
const _stockValuationSql = '''
SELECT
  p.id AS product_id,
  p.uuid AS uuid,
  p.name AS name,
  p.stock AS stock,
  p.reorder_level AS reorder_level,
  COALESCE(pc.avg_cost, p.cost_price) AS average_cost
FROM products p
LEFT JOIN (
  SELECT product_id, SUM(quantity * unit_cost) / SUM(quantity) AS avg_cost
  FROM stock_movements
  WHERE type = 'PURCHASE' AND unit_cost IS NOT NULL AND quantity > 0
  GROUP BY product_id
) pc ON pc.product_id = p.id
WHERE p.is_active = 1
ORDER BY p.name;
''';

class StockValuationRepositoryImpl implements StockValuationRepository {
  StockValuationRepositoryImpl(this._db);

  final DukaDatabase _db;

  @override
  Stream<List<ProductStockValuation>> watchStockValuation() {
    return _db
        .customSelect(
          _stockValuationSql,
          readsFrom: {_db.products, _db.stockMovements},
        )
        .watch()
        .map((rows) => rows.map(_toValuation).toList());
  }

  ProductStockValuation _toValuation(QueryRow row) {
    final stock = row.read<double>('stock');
    final reorderLevel = row.read<double>('reorder_level');
    final averageCost = row.read<double>('average_cost');

    return ProductStockValuation(
      productId: row.read<int>('product_id'),
      uuid: row.read<String>('uuid'),
      name: row.read<String>('name'),
      stock: stock,
      reorderLevel: reorderLevel,
      averageCost: averageCost,
      stockValue: stock * averageCost,
      isLowStock: stock <= reorderLevel,
    );
  }
}
