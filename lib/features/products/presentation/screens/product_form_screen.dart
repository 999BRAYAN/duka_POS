import 'package:drift/drift.dart' show Value;
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/products/data/providers.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/products/presentation/widgets/category_picker.dart';
import 'package:duka_pos/features/products/presentation/widgets/price_below_cost_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds a product, or edits one when [product] is given.
///
/// Opening stock is only offered when adding: after that, stock moves only
/// through StockMovementRepository.recordMovement so every change keeps an
/// audit row, and this form must not become a second writer of it.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({this.product, super.key});

  final Product? product;

  bool get isEditing => product != null;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _costPrice;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _minSellingPrice;
  late final TextEditingController _openingStock;
  late final TextEditingController _reorderLevel;
  late final TextEditingController _unit;

  int? _categoryId;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _sku = TextEditingController(text: p?.sku ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _costPrice = TextEditingController(text: p == null ? '' : _plain(p.costPrice));
    _sellingPrice = TextEditingController(
      text: p == null ? '' : _plain(p.sellingPrice),
    );
    _minSellingPrice = TextEditingController(
      text: p == null ? '' : _plain(p.minSellingPrice),
    );
    _openingStock = TextEditingController(text: '0');
    _reorderLevel = TextEditingController(text: p == null ? '0' : _plain(p.reorderLevel));
    _unit = TextEditingController(text: p?.unit ?? 'pcs');
    _categoryId = p?.categoryId;
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _barcode,
      _costPrice,
      _sellingPrice,
      _minSellingPrice,
      _openingStock,
      _reorderLevel,
      _unit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController controller, {double fallback = 0}) {
    final text = controller.text.trim();
    if (text.isEmpty) return fallback;
    return double.tryParse(text);
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the product a name.');
      return;
    }

    final cost = _number(_costPrice);
    final selling = _number(_sellingPrice);
    final reorder = _number(_reorderLevel);
    final opening = _number(_openingStock);
    if (cost == null || selling == null || reorder == null || opening == null) {
      setState(() => _error = 'Prices and quantities must be numbers.');
      return;
    }
    if (cost < 0 || selling < 0 || reorder < 0 || opening < 0) {
      setState(() => _error = "Prices and quantities can't be negative.");
      return;
    }
    // Left blank, the floor is the selling price: the common case is a shop
    // that does not haggle, and defaulting to 0 would silently allow giving
    // stock away.
    final minSelling = _minSellingPrice.text.trim().isEmpty
        ? selling
        : _number(_minSellingPrice);
    if (minSelling == null) {
      setState(() => _error = 'The minimum selling price must be a number.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final service = ref.read(productServiceProvider);
      final saved = await saveProductWithPriceConfirmation<Object?>(
        context,
        ({required bool confirmPriceBelowCost}) async {
          if (widget.isEditing) {
            await service.updateProduct(
              widget.product!.copyWith(
                name: name,
                sku: Value(_sku.text.trim().isEmpty ? null : _sku.text.trim()),
                barcode: Value(
                  _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
                ),
                categoryId: Value(_categoryId),
                unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
                costPrice: cost,
                sellingPrice: selling,
                minSellingPrice: minSelling,
                reorderLevel: reorder,
                updatedAt: Value(DateTime.now()),
              ),
              confirmPriceBelowCost: confirmPriceBelowCost,
            );
            return widget.product;
          }

          return service.addProduct(
            name: name,
            sku: _sku.text.trim().isEmpty ? null : _sku.text.trim(),
            barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
            categoryId: _categoryId,
            unit: _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim(),
            costPrice: cost,
            sellingPrice: selling,
            minSellingPrice: minSelling,
            stock: opening,
            reorderLevel: reorder,
            confirmPriceBelowCost: confirmPriceBelowCost,
          );
        },
      );

      // Null means the below-cost confirmation was declined — the product
      // was not saved, so the form stays open with the values intact.
      if (saved == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }
      if (mounted) Navigator.of(context).pop();
    } on UnauthorizedException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the product: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit product' : 'Add product'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Product name'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _sku,
                            decoration: const InputDecoration(
                              labelText: 'SKU (optional)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _barcode,
                            decoration: const InputDecoration(
                              labelText: 'Barcode (optional)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CategoryPicker(
                            categories: categories,
                            selectedId: _categoryId,
                            onChanged: (id) => setState(() => _categoryId = id),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _unit,
                            decoration: const InputDecoration(labelText: 'Unit'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Pricing',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _numberField(_costPrice, 'Cost price')),
                        const SizedBox(width: 12),
                        Expanded(child: _numberField(_sellingPrice, 'Selling price')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _numberField(
                      _minSellingPrice,
                      'Lowest price you will accept',
                      helper: 'Leave blank to refuse any discount below the selling price.',
                    ),
                    const SizedBox(height: 20),
                    Text('Stock', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (!widget.isEditing) ...[
                          Expanded(
                            child: _numberField(_openingStock, 'Opening stock'),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: _numberField(
                            _reorderLevel,
                            'Warn me below',
                            helper: 'Shows the product as low stock.',
                          ),
                        ),
                      ],
                    ),
                    if (widget.isEditing) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Stock is changed by sales, goods received and stock '
                        'adjustments, so that every change keeps a record.',
                        style: TextStyle(fontSize: 12, color: AppColors.stone500),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.rust700)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting
                            ? 'Saving…'
                            : widget.isEditing
                            ? 'Save changes'
                            : 'Add product',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String label, {String? helper}) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(labelText: label, helperText: helper),
    );
  }
}
