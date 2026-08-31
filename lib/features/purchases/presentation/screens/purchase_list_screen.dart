import 'package:duka_pos/core/authorization/presentation/acting_as_badge.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/purchases/presentation/providers/purchase_list_providers.dart';
import 'package:duka_pos/features/purchases/presentation/screens/receive_stock_screen.dart';
import 'package:duka_pos/features/purchases/presentation/widgets/payment_status_chip.dart';
import 'package:duka_pos/features/suppliers/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');
final _dateFormat = DateFormat('d MMM yyyy');

/// Purchase order history for a desktop browser window, in the same dense
/// table style as the product list screen.
class PurchaseListScreen extends ConsumerStatefulWidget {
  const PurchaseListScreen({super.key});

  @override
  ConsumerState<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends ConsumerState<PurchaseListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(purchaseSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(filteredPurchasesProvider);
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final suppliers = suppliersAsync.valueOrNull ?? const <Supplier>[];
    final supplierById = {for (final s in suppliers) s.id: s};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          const ActingAsBadge(),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceiveStockScreen()),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Receive stock'),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterBar(searchController: _searchController),
            const SizedBox(height: 16),
            Expanded(
              child: purchasesAsync.when(
                data: (purchases) => purchases.isEmpty
                    ? const _EmptyState()
                    : _PurchaseTable(purchases: purchases, supplierById: supplierById),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load purchases: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.searchController});

  final TextEditingController searchController;

  static const _statuses = ['paid', 'partial', 'unpaid'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusFilter = ref.watch(purchasePaymentStatusFilterProvider);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: searchController,
            onChanged: (value) =>
                ref.read(purchaseSearchQueryProvider.notifier).state = value,
            decoration: const InputDecoration(
              hintText: 'Search by PO reference or supplier',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            initialValue: statusFilter,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All statuses')),
              for (final status in _statuses)
                DropdownMenuItem(value: status, child: Text(paymentStatusLabel(status))),
            ],
            onChanged: (value) =>
                ref.read(purchasePaymentStatusFilterProvider.notifier).state = value,
          ),
        ),
      ],
    );
  }
}

class _PurchaseTable extends StatelessWidget {
  const _PurchaseTable({required this.purchases, required this.supplierById});

  final List<Purchase> purchases;
  final Map<int, Supplier> supplierById;

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
              DataColumn(label: Text('PO Reference')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Total'), numeric: true),
              DataColumn(label: Text('Amount Paid'), numeric: true),
              DataColumn(label: Text('Status')),
            ],
            rows: [for (final purchase in purchases) _row(purchase)],
          ),
        ),
      ),
    );
  }

  DataRow _row(Purchase purchase) {
    final supplierName = supplierById[purchase.supplierId]?.name ?? '—';

    return DataRow(
      cells: [
        DataCell(Text(purchase.referenceNumber ?? '—')),
        DataCell(Text(supplierName)),
        DataCell(Text(_dateFormat.format(purchase.createdAt))),
        DataCell(Text(_amountFormat.format(purchase.total))),
        DataCell(Text(_amountFormat.format(purchase.amountPaid))),
        DataCell(PaymentStatusChip(paymentStatus: purchase.paymentStatus)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No purchases match your filters.',
        style: TextStyle(color: AppColors.stone500),
      ),
    );
  }
}
