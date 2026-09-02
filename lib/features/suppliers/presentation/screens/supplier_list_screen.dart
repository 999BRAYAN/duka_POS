import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/suppliers/presentation/providers.dart';
import 'package:duka_pos/features/suppliers/presentation/screens/supplier_form_screen.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

/// The people the shop buys from. Until this existed, the supplier picker on
/// the goods-receipt screen read a list nothing could fill.
class SupplierListScreen extends ConsumerWidget {
  const SupplierListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final canManage = ref
        .watch(authorizationServiceProvider)
        .can(Permission.manageProducts);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Suppliers'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SupplierFormScreen()),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add supplier'),
              ),
            ),
        ],
      ),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'suppliers'),
      body: NavRail(destination: 'suppliers', child: suppliersAsync.when(
        data: (suppliers) => suppliers.isEmpty
            ? const Center(
                child: Text('No suppliers yet. Add the shops you buy stock from.'),
              )
            : _table(context, suppliers, canManage),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load suppliers: $error')),
      ),
    ));
  }

  Widget _table(BuildContext context, List<Supplier> suppliers, bool canManage) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 40,
          columns: [
            const DataColumn(label: Text('Supplier')),
            const DataColumn(label: Text('Phone')),
            const DataColumn(label: Text('Owed to them'), numeric: true),
            if (canManage) const DataColumn(label: Text('')),
          ],
          rows: [
            for (final supplier in suppliers)
              DataRow(
                color: supplier.balance > 0
                    ? WidgetStatePropertyAll(AppColors.rust50)
                    : null,
                cells: [
                  DataCell(Text(supplier.name)),
                  DataCell(Text(supplier.phone ?? '—')),
                  DataCell(
                    Text(
                      _amountFormat.format(supplier.balance),
                      style: TextStyle(
                        fontWeight: supplier.balance > 0
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: supplier.balance > 0 ? AppColors.rust700 : null,
                      ),
                    ),
                  ),
                  if (canManage)
                    DataCell(
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SupplierFormScreen(supplier: supplier),
                          ),
                        ),
                        child: const Text('Edit'),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
