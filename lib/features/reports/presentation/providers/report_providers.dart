import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/data/providers.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which report tab ReportsScreen is showing.
enum ReportKind { sales, profitAndLoss, inventory }

final selectedReportPeriodProvider = StateProvider<Period>((ref) => Period.today);

/// The single DateRange every report tab reads from — change the period
/// once here and every tab's query re-runs against the same boundaries,
/// so the numbers on screen always agree with each other.
final selectedDateRangeProvider = Provider<DateRange>((ref) {
  return DateRange.forPeriod(ref.watch(selectedReportPeriodProvider));
});

final salesReportProvider = FutureProvider<SalesReport>((ref) {
  return ref
      .watch(salesReportRepositoryProvider)
      .getSalesReport(ref.watch(selectedDateRangeProvider));
});

final profitAndLossReportProvider = FutureProvider<ProfitAndLossReport>((ref) {
  return ref
      .watch(profitAndLossReportRepositoryProvider)
      .getProfitAndLossReport(ref.watch(selectedDateRangeProvider));
});

final inventoryReportProvider = FutureProvider<InventoryReport>((ref) {
  return ref
      .watch(inventoryReportRepositoryProvider)
      .getInventoryReport(ref.watch(selectedDateRangeProvider));
});
