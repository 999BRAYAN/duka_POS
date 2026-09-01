import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/presentation/acting_as_badge.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/printing/receipt_pdf.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/sales/data/providers.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:duka_pos/features/sales/presentation/providers/held_sales_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

const _paymentMethods = {
  'cash': 'Cash',
  'mpesa': 'M-Pesa',
  'card': 'Card',
  'credit': 'Credit',
};

/// The cashier-facing checkout screen: search/tap products into the shared
/// [cartProvider] cart on the left, review and complete the sale on the
/// right. Everything the cart needs to become a [Sale] — customer,
/// payment method, discount — lives here as local form state; the cart
/// itself stays a plain list so it's usable independent of this screen.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _amountPaidController = TextEditingController(text: '0');
  int? _customerId;
  String _paymentMethod = 'cash';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _amountPaidController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cart = ref.read(cartProvider);
    final user = ref.read(currentUserProvider);
    if (cart.isEmpty) return;

    if (user == null) {
      setState(() => _error = 'No signed-in user.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final discount = double.tryParse(_discountController.text) ?? 0;
    final subtotal = cart.fold<double>(0, (sum, line) => sum + line.lineTotal);
    final total = subtotal - discount;
    // Only a real (non-walk-in) customer can be left with a balance — with
    // no one selected there's nobody to charge the shortfall to, so the
    // sale must be paid in full. See SaleRepository.completeSale's
    // credit-limit check, which triggers on this same balanceDue > 0
    // condition regardless of paymentMethod.
    final amountPaid = _customerId != null
        ? (double.tryParse(_amountPaidController.text) ?? 0)
        : total;

    try {
      final sale = await ref.read(saleServiceProvider).completeSale(
        cart: cart,
        customerId: _customerId,
        userId: user.id,
        paymentMethod: _paymentMethod,
        amountPaid: amountPaid,
        discount: discount,
      );

      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      _discountController.text = '0';
      _amountPaidController.text = '0';
      setState(() => _customerId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale ${sale.invoiceNumber} completed.'),
          // A direct click here is a fresh user gesture, unlike calling
          // Printing.layoutPdf automatically right after the awaited
          // completeSale above — some browsers refuse to open a print/
          // save dialog that isn't a synchronous continuation of a click.
          action: SnackBarAction(label: 'Print receipt', onPressed: () => _printReceipt(sale)),
          duration: const Duration(seconds: 6),
        ),
      );
    } on UnauthorizedException {
      setState(() => _error = "You don't have permission to process a sale.");
    } on InsufficientStockException catch (e) {
      setState(() => _error = e.toString());
    } on PriceBelowFloorException catch (e) {
      setState(() => _error = e.toString());
    } on CustomerRequiredForCreditException catch (e) {
      setState(() => _error = e.toString());
    } on CreditLimitExceededException catch (e) {
      setState(() => _error = e.toString());
    } catch (e) {
      setState(() => _error = 'Could not complete this sale: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _printReceipt(Sale sale) async {
    final items = await ref.read(saleRepositoryProvider).getItemsForSale(sale.id);
    final products = ref.read(productsStreamProvider).valueOrNull ?? const <Product>[];
    final productsById = {for (final product in products) product.id: product};

    Customer? customer;
    if (sale.customerId != null) {
      final customers = ref.read(customersStreamProvider).valueOrNull ?? const <Customer>[];
      for (final candidate in customers) {
        if (candidate.id == sale.customerId) {
          customer = candidate;
          break;
        }
      }
    }

    await printReceipt(
      sale: sale,
      items: items,
      productsById: productsById,
      cashier: ref.read(currentUserProvider),
      customer: customer,
    );
  }

  void _hold() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    String? customerName;
    if (_customerId != null) {
      final customers = ref.read(customersStreamProvider).valueOrNull ?? const <Customer>[];
      for (final customer in customers) {
        if (customer.id == _customerId) {
          customerName = customer.name;
          break;
        }
      }
    }

    ref.read(heldSalesProvider.notifier).hold(
      cart: cart,
      customerId: _customerId,
      customerName: customerName,
      paymentMethod: _paymentMethod,
      discount: double.tryParse(_discountController.text) ?? 0,
      amountPaid: double.tryParse(_amountPaidController.text) ?? 0,
    );

    ref.read(cartProvider.notifier).clear();
    _discountController.text = '0';
    _amountPaidController.text = '0';
    setState(() {
      _customerId = null;
      _paymentMethod = 'cash';
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sale held.')),
    );
  }

  void _resumeHeldSale(int id) {
    final held = ref.read(heldSalesProvider.notifier).resume(id);
    if (held == null) return;

    ref.read(cartProvider.notifier).replaceAll(held.cart);
    _discountController.text = held.discount.toString();
    _amountPaidController.text = held.amountPaid.toString();
    setState(() {
      _customerId = held.customerId;
      _paymentMethod = held.paymentMethod;
      _error = null;
    });
  }

  void _showHeldSales() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Held sales'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: Consumer(
            builder: (context, ref, _) {
              final held = ref.watch(heldSalesProvider);
              if (held.isEmpty) {
                return Center(
                  child: Text('No held sales.', style: TextStyle(color: AppColors.stone500)),
                );
              }
              return ListView.separated(
                itemCount: held.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final sale = held[index];
                  return ListTile(
                    title: Text(sale.customerName ?? 'Walk-in customer'),
                    subtitle: Text(
                      '${sale.itemCount.toStringAsFixed(0)} item(s) · '
                      '${_amountFormat.format(sale.subtotal)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Discard',
                          onPressed: () => ref.read(heldSalesProvider.notifier).discard(sale.id),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _resumeHeldSale(sale.id);
                          },
                          child: const Text('Resume'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final discount = double.tryParse(_discountController.text) ?? 0;
    final total = subtotal - discount;

    final productsAsync = ref.watch(productsStreamProvider);
    final customersAsync = ref.watch(customersStreamProvider);
    // The seeded walk-in row (see seedWalkInCustomer) is excluded here — the
    // dropdown's own "Walk-in customer" (null) option already covers it.
    final customers = (customersAsync.valueOrNull ?? const <Customer>[])
        .where((c) => !c.isWalkIn)
        .toList();

    final query = _searchController.text.trim().toLowerCase();
    final products = productsAsync.valueOrNull ?? const <Product>[];
    final filteredProducts = query.isEmpty
        ? products
        : products.where((product) {
            final haystack = [product.name, product.sku ?? ''].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final count = ref.watch(heldSalesProvider).length;
              return IconButton(
                icon: Badge(
                  label: Text('$count'),
                  isLabelVisible: count > 0,
                  child: const Icon(Icons.pause_circle_outline),
                ),
                tooltip: 'Held sales',
                onPressed: _showHeldSales,
              );
            },
          ),
          const ActingAsBadge(),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Search products by name or SKU',
                      prefixIcon: Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: productsAsync.when(
                      data: (_) => filteredProducts.isEmpty
                          ? Center(
                              child: Text(
                                'No products match your search.',
                                style: TextStyle(color: AppColors.stone500),
                              ),
                            )
                          : _ProductPickerGrid(
                              products: filteredProducts,
                              onTap: (product) => ref.read(cartProvider.notifier).addProduct(
                                productId: product.id,
                                name: product.name,
                                price: product.sellingPrice,
                              ),
                            ),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(child: Text('Failed to load products: $error')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 400,
              child: _CartPanel(
                cart: cart,
                subtotal: subtotal,
                discount: discount,
                total: total,
                discountController: _discountController,
                amountPaidController: _amountPaidController,
                customers: customers,
                customerId: _customerId,
                paymentMethod: _paymentMethod,
                submitting: _submitting,
                error: _error,
                onCustomerChanged: (id) => setState(() {
                  // Default a newly-picked customer to "paid in full" — the
                  // cashier has to deliberately lower this to leave a
                  // balance, rather than every named-customer sale silently
                  // becoming unpaid credit. Deselecting back to walk-in
                  // hides the field again (see amountPaid above), so its
                  // text no longer matters.
                  final wasWalkIn = _customerId == null;
                  _customerId = id;
                  if (id != null && wasWalkIn) {
                    _amountPaidController.text = total.toStringAsFixed(2);
                  } else if (id == null) {
                    _amountPaidController.text = '0';
                  }
                }),
                onPaymentMethodChanged: (value) =>
                    setState(() => _paymentMethod = value ?? 'cash'),
                onDiscountChanged: (_) => setState(() {}),
                onAmountPaidChanged: (_) => setState(() {}),
                onQuantityChanged: (productId, quantity) =>
                    ref.read(cartProvider.notifier).setQuantity(productId, quantity),
                onRemoveLine: (productId) =>
                    ref.read(cartProvider.notifier).removeLine(productId),
                onHold: _hold,
                onSubmit: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPickerGrid extends StatelessWidget {
  const _ProductPickerGrid({required this.products, required this.onTap});

  final List<Product> products;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 92,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final outOfStock = product.stock <= 0;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap(product),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    _amountFormat.format(product.sellingPrice),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    outOfStock ? 'Out of stock' : 'Stock: ${_amountFormat.format(product.stock)}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: outOfStock ? AppColors.rust700 : AppColors.stone500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.discountController,
    required this.amountPaidController,
    required this.customers,
    required this.customerId,
    required this.paymentMethod,
    required this.submitting,
    required this.error,
    required this.onCustomerChanged,
    required this.onPaymentMethodChanged,
    required this.onDiscountChanged,
    required this.onAmountPaidChanged,
    required this.onQuantityChanged,
    required this.onRemoveLine,
    required this.onHold,
    required this.onSubmit,
  });

  final List<CartLine> cart;
  final double subtotal;
  final double discount;
  final double total;
  final TextEditingController discountController;
  final TextEditingController amountPaidController;
  final List<Customer> customers;
  final int? customerId;
  final String paymentMethod;
  final bool submitting;
  final String? error;
  final ValueChanged<int?> onCustomerChanged;
  final ValueChanged<String?> onPaymentMethodChanged;
  final ValueChanged<String> onDiscountChanged;
  final ValueChanged<String> onAmountPaidChanged;
  final void Function(int productId, double quantity) onQuantityChanged;
  final ValueChanged<int> onRemoveLine;
  final VoidCallback onHold;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final amountPaid = double.tryParse(amountPaidController.text) ?? 0;
    final balanceDue = total - amountPaid;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cart', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cart.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No items yet.',
                            style: TextStyle(color: AppColors.stone500),
                          ),
                        ),
                      )
                    else
                      for (var i = 0; i < cart.length; i++) ...[
                        _CartLineRow(
                          line: cart[i],
                          onQuantityChanged: (quantity) =>
                              onQuantityChanged(cart[i].productId, quantity),
                          onRemove: () => onRemoveLine(cart[i].productId),
                        ),
                        if (i != cart.length - 1) const Divider(height: 1),
                      ],
                    const Divider(height: 24),
                    DropdownButtonFormField<int?>(
                      initialValue: customerId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Customer', isDense: true),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Walk-in customer')),
                        for (final customer in customers)
                          DropdownMenuItem(value: customer.id, child: Text(customer.name)),
                      ],
                      onChanged: onCustomerChanged,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        isDense: true,
                      ),
                      items: [
                        for (final entry in _paymentMethods.entries)
                          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                      ],
                      onChanged: onPaymentMethodChanged,
                    ),
                    // Only shown once a real customer is picked — with no
                    // one to bill, the sale must be paid in full (see
                    // amountPaid in _SaleScreenState._submit).
                    if (customerId != null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountPaidController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount paid',
                          isDense: true,
                        ),
                        onChanged: onAmountPaidChanged,
                      ),
                      if (balanceDue > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Remaining ${_amountFormat.format(balanceDue)} will be added to '
                          "this customer's balance.",
                          style: TextStyle(fontSize: 11.5, color: AppColors.amber800),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Discount', isDense: true),
                      onChanged: onDiscountChanged,
                    ),
                    const SizedBox(height: 16),
                    _TotalsRow(label: 'Subtotal', value: subtotal),
                    _TotalsRow(label: 'Discount', value: discount),
                    _TotalsRow(label: 'Total', value: total, emphasize: true),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: const TextStyle(color: AppColors.rust700)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: submitting || cart.isEmpty ? null : onHold,
                    child: const Text('Hold sale'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: submitting || cart.isEmpty ? null : onSubmit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Complete sale'),
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

class _CartLineRow extends StatelessWidget {
  const _CartLineRow({required this.line, required this.onQuantityChanged, required this.onRemove});

  final CartLine line;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${_amountFormat.format(line.price)} each',
                  style: TextStyle(fontSize: 12, color: AppColors.stone500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onQuantityChanged(line.quantity - 1),
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          Text(_amountFormat.format(line.quantity)),
          IconButton(
            onPressed: () => onQuantityChanged(line.quantity + 1),
            icon: const Icon(Icons.add_circle_outline, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 72,
            child: Text(
              _amountFormat.format(line.lineTotal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove line',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final double value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_amountFormat.format(value), style: style),
        ],
      ),
    );
  }
}
