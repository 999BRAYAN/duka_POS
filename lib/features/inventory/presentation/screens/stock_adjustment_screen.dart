import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/inventory/data/providers.dart';
import 'package:duka_pos/features/inventory/domain/exceptions.dart';
import 'package:duka_pos/features/inventory/presentation/providers.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _quantityFormat = NumberFormat('#,##0.###');
final _timeFormat = DateFormat('d MMM, HH:mm');

/// Manual stock corrections: breakage, spoilage, theft, and the miscounts
/// that turn up when someone actually counts the shelf.
///
/// Without this screen the stock figure could only ever move through sales
/// and deliveries, so it drifted away from reality with no way back. Every
/// correction demands a reason, because the reason is the only record of
/// what happened to the goods.
class StockAdjustmentScreen extends ConsumerStatefulWidget {
  const StockAdjustmentScreen({super.key});

  @override
  ConsumerState<StockAdjustmentScreen> createState() => _StockAdjustmentScreenState();
}

class _StockAdjustmentScreenState extends ConsumerState<StockAdjustmentScreen> {
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  int? _productId;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(List<Product> products) async {
    if (_submitting) return;

    final product = products.where((p) => p.id == _productId).firstOrNull;
    if (product == null) {
      setState(() => _error = 'Choose the product being corrected.');
      return;
    }
    final change = double.tryParse(_quantity.text.trim());
    if (change == null || change == 0) {
      setState(() => _error = 'Enter how much to add or remove.');
      return;
    }
    if (product.stock + change < 0) {
      setState(
        () => _error =
            'That would take ${product.name} below zero. It has ${_quantityFormat.format(product.stock)} on hand.',
      );
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await ref.read(inventoryServiceProvider).adjustStock(
        productId: product.id,
        quantityChange: change,
        reason: _reason.text,
        userId: ref.read(currentUserProvider)?.id,
      );
      if (!mounted) return;
      _quantity.clear();
      _reason.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${product.name} corrected.')),
      );
    } on UnauthorizedException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } on MissingAdjustmentReasonException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not record the correction: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final movementsAsync = ref.watch(recentMovementsProvider);
    final canAdjust = ref.watch(authorizationServiceProvider).can(Permission.adjustStock);

    return Scaffold(
      appBar: AppBar(title: const Text('Stock adjustments')),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'adjust'),
      body: NavRail(destination: 'adjust', child: !canAdjust
          ? const Center(child: Text('Only a manager can correct stock counts.'))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final form = _form(context, products);
                  final history = _history(movementsAsync, products);

                  if (constraints.maxWidth < 900) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [form, const SizedBox(height: 16), SizedBox(height: 360, child: history)],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 360, child: form),
                      const SizedBox(width: 16),
                      Expanded(child: history),
                    ],
                  );
                },
              ),
            ),
    ));
  }

  Widget _form(BuildContext context, List<Product> products) {
    final selected = products.where((p) => p.id == _productId).firstOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Correct a stock count', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'For breakage, spoilage, theft or a miscount.',
              style: TextStyle(fontSize: 12, color: SemanticColors.muted(context)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Product'),
              items: [
                for (final product in products)
                  DropdownMenuItem(
                    value: product.id,
                    child: Text(
                      '${product.name} — ${_quantityFormat.format(product.stock)} ${product.unit}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _productId = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
              decoration: InputDecoration(
                labelText: 'Change',
                helperText: selected == null
                    ? 'Negative removes stock, positive adds it.'
                    : 'e.g. -3 for three broken. On hand: '
                          '${_quantityFormat.format(selected.stock)} ${selected.unit}',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. 3 lengths cracked in the store',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: SemanticColors.debt(context))),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : () => _submit(products),
              child: Text(_submitting ? 'Saving…' : 'Record correction'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _history(AsyncValue<List<StockMovement>> movementsAsync, List<Product> products) {
    final productById = {for (final p in products) p.id: p};

    return movementsAsync.when(
      data: (movements) {
        final adjustments = movements.where((m) => m.type == 'ADJUSTMENT').toList();
        if (adjustments.isEmpty) {
          return Card(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No corrections recorded yet.',
                  style: TextStyle(color: SemanticColors.muted(context)),
                ),
              ),
            ),
          );
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 56,
              columns: const [
                DataColumn(label: Text('When')),
                DataColumn(label: Text('Product')),
                DataColumn(label: Text('Change'), numeric: true),
                DataColumn(label: Text('Reason')),
              ],
              rows: [
                for (final movement in adjustments)
                  DataRow(
                    cells: [
                      DataCell(Text(_timeFormat.format(movement.createdAt))),
                      DataCell(Text(productById[movement.productId]?.name ?? '—')),
                      DataCell(
                        Text(
                          '${movement.quantity > 0 ? '+' : ''}'
                          '${_quantityFormat.format(movement.quantity)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: movement.quantity < 0
                                ? SemanticColors.debt(context)
                                : SemanticColors.positive(context),
                          ),
                        ),
                      ),
                      DataCell(Text(movement.notes ?? '—')),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load corrections: $error')),
    );
  }
}
