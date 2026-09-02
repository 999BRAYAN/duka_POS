import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/purchases/presentation/providers/purchase_list_providers.dart';
import 'package:duka_pos/features/purchases/presentation/screens/receive_stock_screen.dart';
import 'package:duka_pos/features/purchases/presentation/widgets/payment_status_chip.dart';
import 'package:duka_pos/features/purchases/presentation/widgets/record_purchase_payment_dialog.dart';
import 'package:duka_pos/features/suppliers/presentation/providers.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
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
    final canReceiveStock = ref
        .watch(authorizationServiceProvider)
        .can(Permission.receiveStock);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
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
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'purchases'),
      body: NavRail(destination: 'purchases', child: Padding(
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
                    : _PurchaseTable(
                        purchases: purchases,
                        supplierById: supplierById,
                        canReceiveStock: canReceiveStock,
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load purchases: $error')),
              ),
            ),
          ],
        ),
      ),
    ));
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
  const _PurchaseTable({
    required this.purchases,
    required this.supplierById,
    required this.canReceiveStock,
  });

  final List<Purchase> purchases;
  final Map<int, Supplier> supplierById;
  final bool canReceiveStock;

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
            columns: [
              const DataColumn(label: Text('PO Reference')),
              const DataColumn(label: Text('Supplier')),
              const DataColumn(label: Text('Date')),
              const DataColumn(label: Text('Total'), numeric: true),
              const DataColumn(label: Text('Amount Paid'), numeric: true),
              const DataColumn(label: Text('Status')),
              if (canReceiveStock) const DataColumn(label: Text('')),
            ],
            rows: [for (final purchase in purchases) _row(context, purchase)],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, Purchase purchase) {
    final supplierName = supplierById[purchase.supplierId]?.name ?? '—';
    // Only a received purchase carries a real debt to settle, and only when
    // something is still owed — a fully paid one has nothing left to record.
    final canRecordPayment =
        canReceiveStock && purchase.status == 'received' && purchase.paymentStatus != 'paid';

    return DataRow(
      cells: [
        DataCell(Text(purchase.referenceNumber ?? '—')),
        DataCell(Text(supplierName)),
        DataCell(Text(_dateFormat.format(purchase.createdAt))),
        DataCell(Text(_amountFormat.format(purchase.total))),
        DataCell(Text(_amountFormat.format(purchase.amountPaid))),
        DataCell(PaymentStatusChip(paymentStatus: purchase.paymentStatus)),
        if (canReceiveStock)
          DataCell(
            canRecordPayment
                ? TextButton(
                    onPressed: () => showRecordPurchasePaymentDialog(
                      context,
                      purchase: purchase,
                    ),
                    child: const Text('Record payment'),
                  )
                : const SizedBox.shrink(),
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
      child: Text(
        'No purchases match your filters.',
        style: TextStyle(color: AppColors.stone500),
      ),
    );
  }
}
