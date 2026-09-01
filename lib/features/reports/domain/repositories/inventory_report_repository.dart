import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';

/// Current stock levels plus what moved in a [DateRange] — see
/// [InventoryReport]. Callers should build the range with
/// [DateRange.forPeriod] rather than computing their own boundaries.
abstract interface class InventoryReportRepository {
  Future<InventoryReport> getInventoryReport(DateRange range);
}
