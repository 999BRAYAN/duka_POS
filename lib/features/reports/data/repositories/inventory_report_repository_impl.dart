import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_valuation_repository.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';
import 'package:duka_pos/features/reports/domain/repositories/inventory_report_repository.dart';

class InventoryReportRepositoryImpl implements InventoryReportRepository {
  InventoryReportRepositoryImpl(this._db, this._stockValuation);

  final DukaDatabase _db;
  final StockValuationRepository _stockValuation;

  @override
  Future<InventoryReport> getInventoryReport(DateRange range) async {
    // watchStockValuation() is a live query; taking its first emission
    // reuses that view exactly rather than recomputing average cost and
    // low-stock status here too.
    final stockLevels = await _stockValuation.watchStockValuation().first;

    final type = _db.stockMovements.type;
    final totalQuantity = _db.stockMovements.quantity.sum();

    final rows = await (_db.selectOnly(_db.stockMovements)
          ..addColumns([type, totalQuantity])
          ..where(_db.stockMovements.createdAt.isBetweenValues(range.start, range.end))
          ..groupBy([type]))
        .get();

    return InventoryReport(
      stockLevels: stockLevels,
      movementSummary: [
        for (final row in rows)
          MovementTypeSummary(
            type: row.read(type)!,
            // SUM evaluates to NULL only if the group were empty, which
            // can't happen here — a GROUP BY row only exists because at
            // least one movement of that type matched.
            totalQuantity: row.read(totalQuantity) ?? 0,
          ),
      ],
    );
  }
}
