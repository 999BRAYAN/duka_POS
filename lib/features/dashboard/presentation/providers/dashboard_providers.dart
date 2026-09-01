import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/inventory/presentation/providers.dart';
import 'package:duka_pos/features/reports/data/providers.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final todaySalesReportProvider = FutureProvider<SalesReport>((ref) {
  return ref
      .watch(salesReportRepositoryProvider)
      .getSalesReport(DateRange.forPeriod(Period.today));
});

final todayProfitAndLossReportProvider = FutureProvider<ProfitAndLossReport>((ref) {
  return ref
      .watch(profitAndLossReportRepositoryProvider)
      .getProfitAndLossReport(DateRange.forPeriod(Period.today));
});

final lowStockCountProvider = Provider<AsyncValue<int>>((ref) {
  return ref
      .watch(stockValuationStreamProvider)
      .whenData((levels) => levels.where((l) => l.isLowStock).length);
});

final creditOutstandingTotalProvider = Provider<AsyncValue<double>>((ref) {
  return ref
      .watch(customersWithOutstandingBalanceStreamProvider)
      .whenData((customers) => customers.fold<double>(0, (sum, c) => sum + c.currentBalance));
});

/// One point of the 7-day revenue trend: [date] is that day's own midnight,
/// [revenue] is that single day's SalesReport.totalRevenue. Each point is
/// built from `DateRange.forPeriod(Period.today, date)` — the same
/// day-boundary logic every other report uses, just re-anchored to a past
/// date instead of leaving the reference at now.
typedef DailyRevenue = ({DateTime date, double revenue});

/// The last 7 days including today, oldest first.
final sevenDayRevenueTrendProvider = FutureProvider<List<DailyRevenue>>((ref) async {
  final repository = ref.watch(salesReportRepositoryProvider);
  final today = DateTime.now();

  final points = <DailyRevenue>[];
  for (var daysAgo = 6; daysAgo >= 0; daysAgo--) {
    final day = DateTime(today.year, today.month, today.day - daysAgo);
    final report = await repository.getSalesReport(DateRange.forPeriod(Period.today, day));
    points.add((date: day, revenue: report.totalRevenue));
  }
  return points;
});
