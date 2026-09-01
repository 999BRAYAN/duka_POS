import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/presentation/account_menu.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/expenses/data/providers.dart';
import 'package:duka_pos/features/expenses/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');
final _dateFormat = DateFormat('d MMM yyyy');

/// What the shop spends that isn't stock: rent, transport, power, licences.
///
/// Until this screen existed nothing could record an expense, so the
/// profit-and-loss report's Expenses line was structurally always zero and
/// net profit was overstated by the shop's entire cost base.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  /// The recurring costs of a small shop. Free text is still allowed, since
  /// no fixed list survives contact with a real business.
  static const _commonCategories = [
    'Rent',
    'Transport',
    'Utilities',
    'Wages',
    'Licences',
    'Repairs',
    'Other',
  ];

  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'Rent';
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter how much was spent.');
      return;
    }
    if (_description.text.trim().isEmpty) {
      setState(() => _error = 'Say what the money was for.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await ref.read(expenseServiceProvider).addExpense(
        category: _category,
        description: _description.text.trim(),
        amount: amount,
        userId: ref.read(currentUserProvider)?.id,
      );
      if (!mounted) return;
      _description.clear();
      _amount.clear();
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Expense recorded.')));
    } on UnauthorizedException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not record the expense: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesStreamProvider);
    final canManage = ref
        .watch(authorizationServiceProvider)
        .can(Permission.manageExpenses);

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses'), actions: const [AccountMenu()]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final form = canManage ? _form(context) : const SizedBox.shrink();
            final list = _list(expensesAsync);

            // Side by side on a counter-sized window, stacked when narrow —
            // the form is fixed-height and the list is not, so stacking
            // needs the whole column to scroll.
            if (constraints.maxWidth < 900) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    form,
                    const SizedBox(height: 16),
                    SizedBox(height: 420, child: list),
                  ],
                ),
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: form),
                const SizedBox(width: 16),
                Expanded(child: list),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Record an expense', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in _commonCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'Other'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'e.g. matatu fare to the wholesaler',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.rust700)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(_submitting ? 'Saving…' : 'Record expense'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(AsyncValue<List<Expense>> expensesAsync) {
    return expensesAsync.when(
      data: (expenses) {
        if (expenses.isEmpty) {
          return Card(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No expenses recorded yet.\nRent, transport and power belong here — '
                  'they come off your profit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.stone500),
                ),
              ),
            ),
          );
        }

        final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('All expenses', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      _amountFormat.format(total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 40,
                    columns: const [
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Category')),
                      DataColumn(label: Text('Description')),
                      DataColumn(label: Text('Amount'), numeric: true),
                    ],
                    rows: [
                      for (final expense in expenses)
                        DataRow(
                          cells: [
                            DataCell(Text(_dateFormat.format(expense.createdAt))),
                            DataCell(Text(expense.category)),
                            DataCell(Text(expense.description)),
                            DataCell(Text(_amountFormat.format(expense.amount))),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load expenses: $error')),
    );
  }
}
