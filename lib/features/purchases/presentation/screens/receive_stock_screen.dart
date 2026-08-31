import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/purchases/data/providers.dart';
import 'package:duka_pos/features/suppliers/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

class _LineItemForm {
  _LineItemForm() : id = _nextId++;

  static int _nextId = 0;
  final int id;
  int? productId;
  final quantityController = TextEditingController(text: '1');
  final unitCostController = TextEditingController();

  double get quantity => double.tryParse(quantityController.text) ?? 0;
  double get unitCost => double.tryParse(unitCostController.text) ?? 0;
  double get lineTotal => quantity * unitCost;

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
  }
}

/// Records stock received from a supplier: supplier picker, repeatable line
/// items (product, qty, unit cost — auto-computing each line's total and a
/// running order total), payment status, submit. Product picker is a plain
/// dropdown for now — search comes once the happy path is proven out.
class ReceiveStockScreen extends ConsumerStatefulWidget {
  const ReceiveStockScreen({super.key});

  @override
  ConsumerState<ReceiveStockScreen> createState() => _ReceiveStockScreenState();
}

class _ReceiveStockScreenState extends ConsumerState<ReceiveStockScreen> {
  int? _supplierId;
  String? _paymentStatus = 'paid';
  final _amountPaidController = TextEditingController();
  final List<_LineItemForm> _lines = [_LineItemForm()];
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountPaidController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);

  void _addLine() => setState(() => _lines.add(_LineItemForm()));

  void _removeLine(_LineItemForm line) {
    if (_lines.length == 1) return;
    setState(() {
      _lines.remove(line);
      line.dispose();
    });
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    final validLines = _lines.where((l) => l.productId != null && l.quantity > 0).toList();

    if (_supplierId == null) {
      setState(() => _error = 'Select a supplier.');
      return;
    }
    if (validLines.isEmpty) {
      setState(() => _error = 'Add at least one line item with a product and quantity.');
      return;
    }
    if (_paymentStatus == null) {
      setState(() => _error = 'Select a payment status.');
      return;
    }
    if (user == null) {
      setState(() => _error = 'No signed-in user.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final total = validLines.fold<double>(0, (sum, l) => sum + l.lineTotal);
    final amountPaid = switch (_paymentStatus!) {
      'paid' => total,
      'unpaid' => 0.0,
      _ => double.tryParse(_amountPaidController.text) ?? 0,
    };

    try {
      await ref.read(purchaseServiceProvider).receiveStock(
        supplierId: _supplierId!,
        userId: user.id,
        items: [
          for (final line in validLines)
            PurchaseItemsCompanion.insert(
              uuid: 'placeholder',
              purchaseId: 0,
              productId: line.productId!,
              quantity: line.quantity,
              unitCost: line.unitCost,
              total: line.lineTotal,
              createdAt: DateTime.now(),
            ),
        ],
        paymentStatus: _paymentStatus!,
        amountPaid: amountPaid,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stock received.')),
      );
      Navigator.of(context).pop();
    } on UnauthorizedException {
      setState(() => _error = "You don't have permission to receive stock.");
    } catch (e) {
      setState(() => _error = 'Could not save this receipt: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersStreamProvider);
    final productsAsync = ref.watch(productsStreamProvider);
    final suppliers = suppliersAsync.valueOrNull ?? const <Supplier>[];
    final products = productsAsync.valueOrNull ?? const <Product>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Receive stock')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SupplierField(
                  suppliers: suppliers,
                  selectedId: _supplierId,
                  onChanged: (id) => setState(() => _supplierId = id),
                ),
                const SizedBox(height: 20),
                Text('Line items', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (final line in _lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LineItemRow(
                      key: ValueKey(line.id),
                      line: line,
                      products: products,
                      canRemove: _lines.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () => _removeLine(line),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add line'),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: ${_amountFormat.format(_total)}',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 20),
                _PaymentStatusField(
                  value: _paymentStatus,
                  amountPaidController: _amountPaidController,
                  onChanged: (value) => setState(() => _paymentStatus = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.rust700)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Receive stock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupplierField extends StatelessWidget {
  const _SupplierField({
    required this.suppliers,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Supplier> suppliers;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Supplier',
          helperText: 'No suppliers yet — add one before receiving stock.',
        ),
        child: Text('—', style: TextStyle(color: AppColors.stone400)),
      );
    }

    return DropdownButtonFormField<int>(
      initialValue: selectedId,
      decoration: const InputDecoration(labelText: 'Supplier'),
      items: [
        for (final supplier in suppliers)
          DropdownMenuItem(value: supplier.id, child: Text(supplier.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    super.key,
    required this.line,
    required this.products,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _LineItemForm line;
  final List<Product> products;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 4,
          child: DropdownButtonFormField<int>(
            initialValue: line.productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product', isDense: true),
            items: [
              for (final product in products)
                DropdownMenuItem(value: product.id, child: Text(product.name)),
            ],
            onChanged: (value) {
              line.productId = value;
              onChanged();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: line.quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Qty', isDense: true),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: line.unitCostController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Unit cost', isDense: true),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _amountFormat.format(line.lineTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          onPressed: canRemove ? onRemove : null,
          icon: const Icon(Icons.close, size: 18),
          tooltip: 'Remove line',
        ),
      ],
    );
  }
}

class _PaymentStatusField extends StatelessWidget {
  const _PaymentStatusField({
    required this.value,
    required this.amountPaidController,
    required this.onChanged,
  });

  final String? value;
  final TextEditingController amountPaidController;
  final ValueChanged<String?> onChanged;

  static const _options = {
    'paid': 'Paid',
    'partial': 'Partially paid',
    'unpaid': 'Credit',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            decoration: const InputDecoration(labelText: 'Payment status'),
            items: [
              for (final entry in _options.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: onChanged,
          ),
        ),
        if (value == 'partial') ...[
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: amountPaidController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount paid'),
            ),
          ),
        ],
      ],
    );
  }
}
