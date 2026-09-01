import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';

/// Sales performance for a [DateRange] — see [SalesReport]. Callers should
/// build the range with [DateRange.forPeriod] rather than computing their
/// own boundaries.
abstract interface class SalesReportRepository {
  Future<SalesReport> getSalesReport(DateRange range);
}
