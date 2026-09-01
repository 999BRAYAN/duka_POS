import 'package:duka_pos/core/authorization/presentation/account_menu.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/credit/presentation/screens/receive_payment_screen.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_statement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

/// Customer directory for a desktop browser window, same dense table style
/// as the product/purchase list screens.
class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: ref.read(customerSearchQueryProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(filteredCustomersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          const AccountMenu(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const CustomerFormScreen())),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Add customer'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => ref.read(customerSearchQueryProvider.notifier).state = value,
                decoration: const InputDecoration(
                  hintText: 'Search by name or phone',
                  prefixIcon: Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: customersAsync.when(
                data: (customers) =>
                    customers.isEmpty ? const _EmptyState() : _CustomerTable(customers: customers),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load customers: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.customers});

  final List<Customer> customers;

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
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('Phone')),
              DataColumn(label: Text('Credit Limit'), numeric: true),
              DataColumn(label: Text('Balance'), numeric: true),
              DataColumn(label: Text('')),
            ],
            rows: [for (final customer in customers) _row(context, customer)],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, Customer customer) {
    final hasBalance = customer.currentBalance > 0;

    return DataRow(
      color: hasBalance ? const WidgetStatePropertyAll(AppColors.rust50) : null,
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(customer.name),
              if (customer.isWalkIn) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.stone100,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Walk-in',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.stone600),
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(Text(customer.phone ?? '—')),
        DataCell(Text(_amountFormat.format(customer.creditLimit))),
        DataCell(
          Text(
            _amountFormat.format(customer.currentBalance),
            style: hasBalance
                ? const TextStyle(color: AppColors.rust700, fontWeight: FontWeight.w600)
                : null,
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined, size: 20),
                tooltip: 'Statement',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CustomerStatementScreen(customer: customer)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.payments_outlined, size: 20),
                tooltip: customer.isWalkIn
                    ? 'The walk-in customer never carries a balance to pay down.'
                    : 'Receive payment',
                onPressed: customer.isWalkIn
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReceivePaymentScreen(customer: customer)),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('No customers match your search.', style: TextStyle(color: AppColors.stone500)),
    );
  }
}
