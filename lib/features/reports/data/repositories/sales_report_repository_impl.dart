import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:duka_pos/features/reports/domain/repositories/sales_report_repository.dart';

// A genuine three-table join+group-by, same reasoning as
// StockValuationRepository's query: easier to read as SQL than as drift's
// typed join builder. The two '?' placeholders are bound (in order) to
// range.start and range.end.
const _productBreakdownSql = '''
SELECT
  p.id AS product_id,
  p.name AS product_name,
  SUM(si.quantity) AS quantity_sold,
  SUM(si.total) AS revenue
FROM sale_items si
JOIN sales s ON s.id = si.sale_id
JOIN products p ON p.id = si.product_id
WHERE s.status = 'completed' AND s.created_at BETWEEN ? AND ?
GROUP BY p.id, p.name
ORDER BY revenue DESC;
''';

class SalesReportRepositoryImpl implements SalesReportRepository {
  SalesReportRepositoryImpl(this._db);

  final DukaDatabase _db;

  @override
  Future<SalesReport> getSalesReport(DateRange range) async {
    final totalRevenue = _db.sales.total.sum();
    final saleCount = countAll();
    final averageSaleValue = _db.sales.total.avg();

    final summary = await (_db.selectOnly(_db.sales)
          ..addColumns([totalRevenue, saleCount, averageSaleValue])
          ..where(
            _db.sales.status.equals('completed') &
                _db.sales.createdAt.isBetweenValues(range.start, range.end),
          ))
        .getSingle();

    final breakdownRows = await _db
        .customSelect(
          _productBreakdownSql,
          variables: [Variable.withDateTime(range.start), Variable.withDateTime(range.end)],
          readsFrom: {_db.saleItems, _db.sales, _db.products},
        )
        .get();

    return SalesReport(
      // SUM/AVG evaluate to NULL (not zero) over an empty group — a report
      // with no completed sales in range should read as all-zero, not null.
      totalRevenue: summary.read(totalRevenue) ?? 0,
      saleCount: summary.read(saleCount) ?? 0,
      averageSaleValue: summary.read(averageSaleValue) ?? 0,
      productBreakdown: [
        for (final row in breakdownRows)
          ProductRevenue(
            productId: row.read<int>('product_id'),
            productName: row.read<String>('product_name'),
            quantitySold: row.read<double>('quantity_sold'),
            revenue: row.read<double>('revenue'),
          ),
      ],
    );
  }
}
