import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/reports/data/repositories/profit_and_loss_report_repository_impl.dart';
import 'package:duka_pos/features/reports/data/repositories/sales_report_repository_impl.dart';
import 'package:duka_pos/features/reports/domain/repositories/profit_and_loss_report_repository.dart';
import 'package:duka_pos/features/reports/domain/repositories/sales_report_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final salesReportRepositoryProvider = Provider<SalesReportRepository>((ref) {
  return SalesReportRepositoryImpl(ref.watch(databaseProvider));
});

final profitAndLossReportRepositoryProvider = Provider<ProfitAndLossReportRepository>((ref) {
  return ProfitAndLossReportRepositoryImpl(ref.watch(databaseProvider));
});
