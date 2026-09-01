import 'dart:math';

import 'package:duka_pos/core/authorization/presentation/account_menu.dart';
import 'package:duka_pos/core/backup/backup.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');
final _compactAmountFormat = NumberFormat.compact();
final _weekdayFormat = DateFormat('E');
final _tooltipDateFormat = DateFormat('d MMM');

/// The shop's at-a-glance status: today's headline numbers alongside a
/// 7-day revenue trend, so a manager can see both "how's today going" and
/// "is that normal" in one screen.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(todaySalesReportProvider);
    final pnlAsync = ref.watch(todayProfitAndLossReportProvider);
    final lowStockAsync = ref.watch(lowStockCountProvider);
    final creditAsync = ref.watch(creditOutstandingTotalProvider);
    final trendAsync = ref.watch(sevenDayRevenueTrendProvider);

    final netProfit = pnlAsync.valueOrNull?.netProfit;
    final lowStockCount = lowStockAsync.valueOrNull ?? 0;
    final creditOutstanding = creditAsync.valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (kIsWeb) ...[
            IconButton(
              icon: const Icon(Icons.backup_outlined),
              tooltip: 'Backup now',
              onPressed: () => _backupNow(context),
            ),
            IconButton(
              icon: const Icon(Icons.restore_page_outlined),
              tooltip: 'Restore from backup',
              onPressed: () => _restoreFromBackup(context, ref),
            ),
          ],
          const AccountMenu(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _KpiCard(
                  label: "Today's revenue",
                  value: _asyncText(salesAsync, (r) => _amountFormat.format(r.totalRevenue)),
                ),
                const SizedBox(width: 16),
                _KpiCard(
                  label: "Today's net profit",
                  value: _asyncText(pnlAsync, (r) => _amountFormat.format(r.netProfit)),
                  valueColor: netProfit != null && netProfit < 0 ? AppColors.rust700 : null,
                ),
                const SizedBox(width: 16),
                _KpiCard(
                  label: 'Low stock',
                  value: _asyncText(lowStockAsync, (n) => n.toString()),
                  valueColor: lowStockCount > 0 ? AppColors.amber800 : null,
                ),
                const SizedBox(width: 16),
                _KpiCard(
                  label: 'Credit outstanding',
                  value: _asyncText(creditAsync, _amountFormat.format),
                  valueColor: creditOutstanding > 0 ? AppColors.rust700 : null,
                ),
              ],
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 16),
              const _BackupReminder(),
            ],
            const SizedBox(height: 24),
            Text('Revenue, last 7 days', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: trendAsync.when(
                data: (points) => _RevenueTrendChart(points: points),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load trend: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _asyncText<T>(AsyncValue<T> value, String Function(T) format) {
    return value.when(data: format, loading: () => '…', error: (_, _) => '—');
  }

  Future<void> _backupNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await downloadDatabaseBackup();
      messenger.showSnackBar(const SnackBar(content: Text('Backup downloaded.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restoreFromBackup(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This will replace all current data with the backup file. '
          'A safety copy of your current data will be downloaded first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Choose backup file'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final db = ref.read(databaseProvider);
    try {
      final outcome = await restoreDatabaseFromPickedFile(
        closeDatabase: db.close,
        currentSchemaVersion: db.schemaVersion,
      );
      if (outcome == RestoreOutcome.cancelled) return;
      // On success the page reloads, so any snackbar here would never be seen.
    } on RestoreAbortedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }
}

/// Says when this device last saved a backup, and gets louder the longer it
/// has been.
///
/// The shop's data lives in one browser profile: clearing site data or
/// losing the machine loses everything not backed up. That risk is invisible
/// until the day it isn't, so it is stated on the screen a manager opens
/// most rather than left in a menu.
class _BackupReminder extends StatelessWidget {
  const _BackupReminder();

  @override
  Widget build(BuildContext context) {
    final last = lastBackupAt();
    final daysAgo = last == null ? null : DateTime.now().difference(last).inDays;
    final stale = daysAgo == null || daysAgo >= 7;

    final message = switch (daysAgo) {
      null => 'This shop has never been backed up on this device.',
      0 => 'Backed up today.',
      1 => 'Last backup was yesterday.',
      _ => 'Last backup was $daysAgo days ago.',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: stale ? AppColors.amber50 : AppColors.stone100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stale ? AppColors.amber200 : AppColors.stone200),
      ),
      child: Row(
        children: [
          Icon(
            stale ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 18,
            color: stale ? AppColors.amber800 : AppColors.stone500,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              stale
                  ? '$message Your sales, stock and customer balances exist only '
                        'in this browser.'
                  : message,
              style: TextStyle(
                fontSize: 13,
                color: stale ? AppColors.amber800 : AppColors.stone600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

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
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: valueColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueTrendChart extends StatelessWidget {
  const _RevenueTrendChart({required this.points});

  final List<DailyRevenue> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Center(
        child: Text('No data yet.', style: TextStyle(color: AppColors.stone500)),
      );
    }

    final maxRevenue = points.fold<double>(0, (max, p) => p.revenue > max ? p.revenue : max);
    final interval = _niceInterval(maxRevenue);
    final maxY = maxRevenue == 0 ? interval : (maxRevenue / interval).ceil() * interval;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 24, 24, 12),
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: interval,
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
                  reservedSize: 48,
                  interval: interval,
                  getTitlesWidget: (value, meta) => Text(
                    _compactAmountFormat.format(value),
                    style: TextStyle(fontSize: 11, color: AppColors.stone500),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= points.length) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _weekdayFormat.format(points[index].date),
                        style: TextStyle(fontSize: 11, color: AppColors.stone500),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.stone800,
                getTooltipItems: (touchedSpots) => [
                  for (final spot in touchedSpots)
                    LineTooltipItem(
                      _amountFormat.format(spot.y),
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      children: [
                        TextSpan(
                          text: '\n${_tooltipDateFormat.format(points[spot.x.round()].date)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].revenue),
                ],
                color: AppColors.amber700,
                barWidth: 2,
                dotData: FlDotData(
                  getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                    radius: 4,
                    color: AppColors.amber700,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.amber700.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A "nice" gridline step for [maxValue] — e.g. 100/200/500/1000 rather
  /// than an arbitrary maxValue/4 that would land ticks on values like
  /// 137.5, contradicting the round-numbers convention every other axis in
  /// this app follows.
  static double _niceInterval(double maxValue) {
    if (maxValue <= 0) return 100;

    final roughStep = maxValue / 4;
    final magnitude = pow(10, (log(roughStep) / ln10).floor()).toDouble();
    final residual = roughStep / magnitude;
    final niceResidual = residual < 1.5
        ? 1.0
        : residual < 3
        ? 2.0
        : residual < 7
        ? 5.0
        : 10.0;
    return niceResidual * magnitude;
  }
}
