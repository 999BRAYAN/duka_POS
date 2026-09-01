import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';

/// A profit-and-loss statement for a [DateRange] — see
/// [ProfitAndLossReport]. Callers should build the range with
/// [DateRange.forPeriod] rather than computing their own boundaries.
abstract interface class ProfitAndLossReportRepository {
  Future<ProfitAndLossReport> getProfitAndLossReport(DateRange range);
}
