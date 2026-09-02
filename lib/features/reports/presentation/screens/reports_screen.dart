import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:duka_pos/features/reports/presentation/providers/report_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _numberFormat = NumberFormat('#,##0.00');

const _periodLabels = {
  Period.today: 'Today',
  Period.week: 'This week',
  Period.month: 'This month',
  Period.year: 'This year',
};

const _movementTypeOrder = ['PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT'];
const _movementTypeLabels = {
  'PURCHASE': 'Received',
  'SALE': 'Sold',
  'RETURN': 'Returned',
  'ADJUSTMENT': 'Adjusted',
};

/// Sales, profit & loss, and inventory reports, all reading from the one
/// [selectedDateRangeProvider] a shared period selector controls — pick a
/// period once and every tab's numbers agree on the same window.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reports'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Sales'), Tab(text: 'Profit & loss'), Tab(text: 'Inventory')],
          ),
        ),
        drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'reports'),
        body: NavRail(destination: 'reports', child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            Padding(padding: EdgeInsets.all(24), child: _PeriodSelector()),
            Expanded(
              child: TabBarView(
                children: [_SalesReportTab(), _ProfitAndLossReportTab(), _InventoryReportTab()],
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedReportPeriodProvider);

    return Wrap(
      spacing: 8,
      children: [
        for (final period in Period.values)
          ChoiceChip(
            label: Text(_periodLabels[period]!),
            selected: selected == period,
            onSelected: (_) => ref.read(selectedReportPeriodProvider.notifier).state = period,
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.stone500)),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesReportTab extends ConsumerWidget {
  const _SalesReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(salesReportProvider);

    return reportAsync.when(
      data: (report) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _StatTile(label: 'Total revenue', value: _numberFormat.format(report.totalRevenue)),
                const SizedBox(width: 16),
                _StatTile(label: 'Sales', value: report.saleCount.toString()),
                const SizedBox(width: 16),
                _StatTile(
                  label: 'Average sale',
                  value: _numberFormat.format(report.averageSaleValue),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Revenue by product', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: report.productBreakdown.isEmpty
                  ? Center(
                      child: Text(
                        'No sales in this period.',
                        style: TextStyle(color: AppColors.stone500),
                      ),
                    )
                  : _ProductBreakdownTable(rows: report.productBreakdown),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load report: $error')),
    );
  }
}

class _ProductBreakdownTable extends StatelessWidget {
  const _ProductBreakdownTable({required this.rows});

  final List<ProductRevenue> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 40,
            columnSpacing: 32,
            horizontalMargin: 16,
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Quantity sold'), numeric: true),
              DataColumn(label: Text('Revenue'), numeric: true),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(Text(row.productName)),
                    DataCell(Text(_numberFormat.format(row.quantitySold))),
                    DataCell(Text(_numberFormat.format(row.revenue))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfitAndLossReportTab extends ConsumerWidget {
  const _ProfitAndLossReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(profitAndLossReportProvider);

    return reportAsync.when(
      data: (report) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PnlRow(label: 'Subtotal', value: report.subtotal),
                    _PnlRow(label: 'Discount', value: -report.discount),
                    const Divider(height: 24),
                    _PnlRow(label: 'Net revenue', value: report.netRevenue, emphasize: true),
                    _PnlRow(label: 'Cost of goods sold', value: -report.cogs),
                    const Divider(height: 24),
                    _PnlRow(label: 'Gross profit', value: report.grossProfit, emphasize: true),
                    _PnlRow(label: 'Expenses', value: -report.expenses),
                    const Divider(height: 24),
                    _PnlRow(
                      label: 'Net profit',
                      value: report.netProfit,
                      emphasize: true,
                      color: report.netProfit < 0 ? AppColors.rust700 : AppColors.green700,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load report: $error')),
    );
  }
}

class _PnlRow extends StatelessWidget {
  const _PnlRow({required this.label, required this.value, this.emphasize = false, this.color});

  final String label;
  final double value;
  final bool emphasize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_numberFormat.format(value), style: style),
        ],
      ),
    );
  }
}

class _InventoryReportTab extends ConsumerWidget {
  const _InventoryReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(inventoryReportProvider);

    return reportAsync.when(
      data: (report) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Stock levels', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: report.stockLevels.isEmpty
                        ? Center(
                            child: Text(
                              'No products yet.',
                              style: TextStyle(color: AppColors.stone500),
                            ),
                          )
                        : _StockLevelsTable(levels: report.stockLevels),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Stock movement', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: report.movementSummary.isEmpty
                        ? Center(
                            child: Text(
                              'No stock movement in this period.',
                              style: TextStyle(color: AppColors.stone500),
                            ),
                          )
                        : _MovementSummaryChart(summary: report.movementSummary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Failed to load report: $error')),
    );
  }
}

class _StockLevelsTable extends StatelessWidget {
  const _StockLevelsTable({required this.levels});

  final List<ProductStockValuation> levels;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 40,
            columnSpacing: 32,
            horizontalMargin: 16,
            columns: const [
              DataColumn(label: Text('Product')),
              DataColumn(label: Text('Stock'), numeric: true),
              DataColumn(label: Text('Avg cost'), numeric: true),
              DataColumn(label: Text('Stock value'), numeric: true),
            ],
            rows: [
              for (final level in levels)
                DataRow(
                  color: level.isLowStock
                      ? const WidgetStatePropertyAll(AppColors.amber50)
                      : null,
                  cells: [
                    DataCell(Text(level.name)),
                    DataCell(Text(_numberFormat.format(level.stock))),
                    DataCell(Text(_numberFormat.format(level.averageCost))),
                    DataCell(Text(_numberFormat.format(level.stockValue))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovementSummaryChart extends StatelessWidget {
  const _MovementSummaryChart({required this.summary});

  final List<MovementTypeSummary> summary;

  @override
  Widget build(BuildContext context) {
    final byType = {for (final s in summary) s.type: s.totalQuantity};
    final bars = [for (final type in _movementTypeOrder) (type: type, quantity: byType[type] ?? 0)];

    final maxAbs = bars.fold<double>(0, (max, b) => b.quantity.abs() > max ? b.quantity.abs() : max);
    final axisBound = maxAbs == 0 ? 1.0 : maxAbs * 1.2;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 16, 12),
        child: BarChart(
          BarChartData(
            minY: -axisBound,
            maxY: axisBound,
            gridData: FlGridData(
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.stone200, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text(
                    value.toStringAsFixed(0),
                    style: TextStyle(fontSize: 11, color: AppColors.stone500),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= bars.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _movementTypeLabels[bars[index].type]!,
                        style: TextStyle(fontSize: 11, color: AppColors.stone500),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => AppColors.stone800,
                getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                  _numberFormat.format(rod.toY),
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < bars.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: bars[i].quantity,
                      width: 24,
                      borderRadius: BorderRadius.circular(4),
                      color: bars[i].quantity < 0 ? AppColors.rust700 : AppColors.green700,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
