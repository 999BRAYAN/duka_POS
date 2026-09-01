/// A profit-and-loss statement for a DateRange, built from the underlying
/// Sales/Expenses sums alone — see ProfitAndLossReportRepository. Nothing
/// below is stored anywhere; netRevenue/grossProfit/netProfit are derived
/// every time this is constructed, so they can never drift out of sync
/// with the rows they're computed from the way a cached column could.
class ProfitAndLossReport {
  const ProfitAndLossReport({
    required this.subtotal,
    required this.discount,
    required this.cogs,
    required this.expenses,
  });

  /// SUM(Sales.subtotal) over completed sales in range.
  final double subtotal;

  /// SUM(Sales.discount) over completed sales in range.
  final double discount;

  /// SUM(Sales.cogs) over completed sales in range.
  final double cogs;

  /// SUM(Expenses.amount) in range.
  final double expenses;

  /// Subtotal net of discounts given at the register.
  double get netRevenue => subtotal - discount;

  /// Net revenue minus the cost of the goods sold to earn it.
  double get grossProfit => netRevenue - cogs;

  /// Gross profit minus operating expenses for the same range.
  double get netProfit => grossProfit - expenses;
}
