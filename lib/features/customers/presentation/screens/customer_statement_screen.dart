import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');
final _dateFormat = DateFormat('d MMM yyyy');

/// A read-only statement of every credit sale and payment that has moved
/// this customer's balance — see CustomerLedgerRepository.
class CustomerStatementScreen extends ConsumerWidget {
  const CustomerStatementScreen({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(customerLedgerProvider(customer.id));

    return Scaffold(
      appBar: AppBar(title: Text('${customer.name} — statement')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryRow(customer: customer),
            const SizedBox(height: 16),
            Expanded(
              child: ledgerAsync.when(
                data: (entries) =>
                    entries.isEmpty ? const _EmptyState() : _LedgerTable(entries: entries),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load statement: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _SummaryTile(label: 'Credit limit', value: customer.creditLimit),
            const SizedBox(width: 32),
            _SummaryTile(
              label: 'Current balance',
              value: customer.currentBalance,
              emphasize: customer.currentBalance > 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value, this.emphasize = false});

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.stone500)),
        const SizedBox(height: 4),
        Text(
          _amountFormat.format(value),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: emphasize ? AppColors.rust700 : null,
          ),
        ),
      ],
    );
  }
}

class _LedgerTable extends StatelessWidget {
  const _LedgerTable({required this.entries});

  final List<CustomerLedgerEntry> entries;

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
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Reference')),
              DataColumn(label: Text('Amount'), numeric: true),
              DataColumn(label: Text('Balance'), numeric: true),
            ],
            rows: [for (final entry in entries) _row(entry)],
          ),
        ),
      ),
    );
  }

  DataRow _row(CustomerLedgerEntry entry) {
    final isCreditSale = entry.type == CustomerLedgerEntryType.creditSale;
    final label = switch (entry.type) {
      CustomerLedgerEntryType.creditSale => 'Credit sale',
      CustomerLedgerEntryType.payment => 'Payment',
      CustomerLedgerEntryType.reversal => 'Sale voided',
    };

    return DataRow(
      cells: [
        DataCell(Text(_dateFormat.format(entry.date))),
        DataCell(
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isCreditSale ? AppColors.rust700 : AppColors.green700,
            ),
          ),
        ),
        DataCell(Text(entry.reference)),
        DataCell(
          Text(
            '${isCreditSale ? '+' : '-'}${_amountFormat.format(entry.amount)}',
          ),
        ),
        DataCell(Text(_amountFormat.format(entry.runningBalance))),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No credit activity yet.', style: TextStyle(color: AppColors.stone500)),
    );
  }
}
