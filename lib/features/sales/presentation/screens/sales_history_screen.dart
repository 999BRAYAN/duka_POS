import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/sales/data/providers.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');
final _dateFormat = DateFormat('d MMM, HH:mm');

/// Every sale the shop has rung up, and the only place a sale can be
/// reversed. Voiding lives here rather than on the checkout screen because
/// it is a correction made after the fact, usually by someone other than
/// whoever rang it up.
class SalesHistoryScreen extends ConsumerWidget {
  const SalesHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesStreamProvider);
    final customers = ref.watch(customersStreamProvider).valueOrNull ?? const <Customer>[];
    final customerById = {for (final c in customers) c.id: c};
    final canVoid = ref.watch(authorizationServiceProvider).can(Permission.voidSale);

    return Scaffold(
      appBar: AppBar(title: const Text('Sales history')),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'sales'),
      body: NavRail(destination: 'sales', child: salesAsync.when(
        data: (sales) => sales.isEmpty
            ? const Center(child: Text('No sales yet.'))
            : _table(context, ref, sales, customerById, canVoid),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load sales: $error')),
      ),
    ));
  }

  Widget _table(
    BuildContext context,
    WidgetRef ref,
    List<Sale> sales,
    Map<int, Customer> customerById,
    bool canVoid,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 42,
            dataRowMaxHeight: 42,
            columns: const [
              DataColumn(label: Text('Receipt')),
              DataColumn(label: Text('When')),
              DataColumn(label: Text('Customer')),
              DataColumn(label: Text('Total'), numeric: true),
              DataColumn(label: Text('Paid'), numeric: true),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final sale in sales)
                _row(context, ref, sale, customerById, canVoid),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
    Map<int, Customer> customerById,
    bool canVoid,
  ) {
    final isVoid = sale.status == 'void';
    final owing = sale.total - sale.amountPaid > 0;
    final muted = SemanticColors.muted(context);

    return DataRow(
      cells: [
        DataCell(
          Text(
            sale.invoiceNumber,
            style: TextStyle(
              decoration: isVoid ? TextDecoration.lineThrough : null,
              color: isVoid ? muted : null,
            ),
          ),
        ),
        DataCell(Text(_dateFormat.format(sale.createdAt))),
        DataCell(
          Text(
            sale.customerId == null
                ? 'Walk-in'
                : customerById[sale.customerId]?.name ?? '—',
          ),
        ),
        DataCell(Text(_amountFormat.format(sale.total))),
        DataCell(Text(_amountFormat.format(sale.amountPaid))),
        DataCell(
          isVoid
              ? Tooltip(
                  message: sale.voidReason ?? 'No reason recorded',
                  child: const Text('Void'),
                )
              : owing
              ? Text(
                  'On account',
                  style: TextStyle(color: SemanticColors.debt(context)),
                )
              : Text(
                  'Paid',
                  style: TextStyle(color: SemanticColors.positive(context)),
                ),
        ),
        DataCell(
          isVoid
              ? const SizedBox.shrink()
              : canVoid
              ? TextButton(
                  onPressed: () => _void(context, ref, sale),
                  child: Text(
                    'Void',
                    style: TextStyle(color: SemanticColors.debt(context)),
                  ),
                )
              : Text('manager only', style: TextStyle(fontSize: 11, color: muted)),
        ),
      ],
    );
  }

  Future<void> _void(BuildContext context, WidgetRef ref, Sale sale) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _VoidDialog(invoiceNumber: sale.invoiceNumber),
    );
    if (reason == null) return;

    try {
      await ref.read(saleServiceProvider).voidSale(
        uuid: sale.uuid,
        reason: reason,
        voidedByUserId: ref.read(currentUserProvider)?.id,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${sale.invoiceNumber} voided. Stock and balance reversed.')),
      );
    } on UnauthorizedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } on SaleAlreadyVoidException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } on MissingVoidReasonException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not void the sale: $e')));
    }
  }
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({required this.invoiceNumber});

  final String invoiceNumber;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Say why this sale is being voided.');
      return;
    }
    // See product_form_screen.dart's _submit for why this unfocus matters —
    // this field still holds focus when the button is clicked with a mouse.
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Void ${widget.invoiceNumber}?'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The goods go back into stock and any unpaid balance comes off the '
              "customer's account. Both are recorded.",
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. wrong item rung up',
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Void sale')),
      ],
    );
  }
}
