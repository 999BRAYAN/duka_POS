import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';
import 'package:duka_pos/features/reports/domain/repositories/profit_and_loss_report_repository.dart';

class ProfitAndLossReportRepositoryImpl implements ProfitAndLossReportRepository {
  ProfitAndLossReportRepositoryImpl(this._db);

  final DukaDatabase _db;

  @override
  Future<ProfitAndLossReport> getProfitAndLossReport(DateRange range) async {
    final subtotal = _db.sales.subtotal.sum();
    final discount = _db.sales.discount.sum();
    final cogs = _db.sales.cogs.sum();

    final salesSummary = await (_db.selectOnly(_db.sales)
          ..addColumns([subtotal, discount, cogs])
          ..where(
            _db.sales.status.equals('completed') &
                _db.sales.createdAt.isBetweenValues(range.start, range.end),
          ))
        .getSingle();

    final expenseTotal = _db.expenses.amount.sum();
    final expenseSummary = await (_db.selectOnly(_db.expenses)
          ..addColumns([expenseTotal])
          ..where(_db.expenses.createdAt.isBetweenValues(range.start, range.end)))
        .getSingle();

    return ProfitAndLossReport(
      // SUM evaluates to NULL over an empty group — no activity in range
      // should read as all-zero, not null.
      subtotal: salesSummary.read(subtotal) ?? 0,
      discount: salesSummary.read(discount) ?? 0,
      cogs: salesSummary.read(cogs) ?? 0,
      expenses: expenseSummary.read(expenseTotal) ?? 0,
    );
  }
}
