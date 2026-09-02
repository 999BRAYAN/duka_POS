import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:duka_pos/features/sales/presentation/providers/held_sales_provider.dart';
import 'package:duka_pos/features/sales/presentation/providers/order_form_providers.dart';
import 'package:duka_pos/features/sales/presentation/screens/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

/// Step one of a sale: put things on the order.
///
/// Payment is deliberately not here. Building the order and taking the money
/// are separate jobs at a counter — the goods are gathered and agreed first,
/// then a total is named and paid — and splitting them means the payment
/// screen can show the order as a settled list to confirm against rather
/// than a cart still being edited underneath the person paying.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _searchController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    final discount = ref.read(orderDiscountProvider);
    if (discount > 0) _discountController.text = _plain(discount);
  }

  static String _plain(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _hold() {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final customerId = ref.read(orderCustomerIdProvider);
    String? customerName;
    if (customerId != null) {
      final customers =
          ref.read(customersStreamProvider).valueOrNull ?? const <Customer>[];
      for (final customer in customers) {
        if (customer.id == customerId) customerName = customer.name;
      }
    }

    ref
        .read(heldSalesProvider.notifier)
        .hold(
          cart: cart,
          customerId: customerId,
          customerName: customerName,
          paymentMethod: ref.read(orderPaymentMethodProvider),
          discount: ref.read(orderDiscountProvider),
          amountPaid: ref.read(orderAmountPaidProvider) ?? 0,
        );

    ref.read(cartProvider.notifier).clear();
    resetOrder(ref);
    _discountController.text = '0';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Order held.')));
  }

  void _resumeHeldSale(int id) {
    final held = ref.read(heldSalesProvider.notifier).resume(id);
    if (held == null) return;

    ref.read(cartProvider.notifier).replaceAll(held.cart);
    ref.read(orderCustomerIdProvider.notifier).state = held.customerId;
    ref.read(orderPaymentMethodProvider.notifier).state = held.paymentMethod;
    ref.read(orderDiscountProvider.notifier).state = held.discount;
    ref.read(orderAmountPaidProvider.notifier).state = held.amountPaid;
    _discountController.text = _plain(held.discount);
    setState(() {});
  }

  void _showHeldSales() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Held orders'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: Consumer(
            builder: (context, ref, _) {
              final held = ref.watch(heldSalesProvider);
              if (held.isEmpty) {
                return Center(
                  child: Text(
                    'No held orders.',
                    style: TextStyle(color: SemanticColors.muted(context)),
                  ),
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
                          onPressed: () => ref
                              .read(heldSalesProvider.notifier)
                              .discard(sale.id),
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

  /// Name, SKU and barcode, so a shop can find a fitting by the code printed
  /// on the box as readily as by what it is called.
  List<Product> _matching(List<Product> products) {
    final query = _searchController.text.trim().toLowerCase();
    return products.where((product) {
      if (_categoryId != null && product.categoryId != _categoryId) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        product.name,
        product.sku ?? '',
        product.barcode ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final discount = ref.watch(orderDiscountProvider);
    final total = (subtotal - discount).clamp(0, double.infinity).toDouble();

    final productsAsync = ref.watch(productsStreamProvider);
    final categories =
        ref.watch(categoriesStreamProvider).valueOrNull ?? const <Category>[];
    final products = productsAsync.valueOrNull ?? const <Product>[];
    final matching = _matching(products);

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
                tooltip: 'Held orders',
                onPressed: _showHeldSales,
              );
            },
          ),
        ],
      ),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'sell'),
      body: NavRail(destination: 'sell', child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _OrderSteps(step: 1),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Below this, the order panel and the product grid cannot
                  // both hold their ground side by side, so the panel goes
                  // underneath rather than squeezing the grid to nothing.
                  final narrow = constraints.maxWidth < 860;
                  final picker = _picker(
                    context,
                    productsAsync,
                    products,
                    matching,
                    categories,
                  );
                  final panel = _panel(
                    context,
                    cart,
                    subtotal,
                    discount,
                    total,
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: picker),
                        const SizedBox(height: 16),
                        SizedBox(height: 300, child: panel),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: picker),
                      const SizedBox(width: 24),
                      SizedBox(width: 360, child: panel),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _picker(
    BuildContext context,
    AsyncValue<List<Product>> productsAsync,
    List<Product> products,
    List<Product> matching,
    List<Category> categories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search by name, SKU or barcode',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          _CategoryFilter(
            categories: categories,
            selectedId: _categoryId,
            countFor: (id) =>
                products.where((p) => id == null || p.categoryId == id).length,
            onChanged: (id) => setState(() => _categoryId = id),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: productsAsync.when(
            data: (_) => matching.isEmpty
                ? Center(
                    child: Text(
                      products.isEmpty
                          ? 'No products yet. Add some from the Products screen.'
                          : 'Nothing matches that search.',
                      style: TextStyle(color: SemanticColors.muted(context)),
                    ),
                  )
                : _ProductPickerGrid(
                    products: matching,
                    onTap: (product) => ref
                        .read(cartProvider.notifier)
                        .addProduct(
                          productId: product.id,
                          name: product.name,
                          price: product.sellingPrice,
                        ),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) =>
                Center(child: Text('Failed to load products: $error')),
          ),
        ),
      ],
    );
  }

  Widget _panel(
    BuildContext context,
    List<CartLine> cart,
    double subtotal,
    double discount,
    double total,
  ) {
    final products =
        ref.read(productsStreamProvider).valueOrNull ?? const <Product>[];

    return _OrderPanel(
      cart: cart,
      subtotal: subtotal,
      discount: discount,
      total: total,
      discountController: _discountController,
      floorFor: (productId) =>
          products.where((p) => p.id == productId).firstOrNull?.minSellingPrice ?? 0,
      onDiscountChanged: (value) =>
          ref.read(orderDiscountProvider.notifier).state =
              double.tryParse(value) ?? 0,
      onQuantityChanged: (productId, quantity) =>
          ref.read(cartProvider.notifier).setQuantity(productId, quantity),
      onPriceChanged: (productId, price) =>
          ref.read(cartProvider.notifier).setPrice(productId, price),
      onRemoveLine: (productId) =>
          ref.read(cartProvider.notifier).removeLine(productId),
      onHold: _hold,
      onReview: cart.isEmpty
          ? null
          : () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CheckoutScreen())),
    );
  }
}

/// Where in the two-step sale the person is. Shown on both screens so the
/// second one doesn't feel like a different place they've been dropped into.
class _OrderSteps extends StatelessWidget {
  const _OrderSteps({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    Widget label(int index, String text) {
      final active = index == step;
      final color = active
          ? Theme.of(context).colorScheme.primary
          : SemanticColors.muted(context);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(color: color),
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active ? Theme.of(context).colorScheme.onPrimary : color,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        label(1, 'Build the order'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(
            Icons.arrow_forward,
            size: 14,
            color: SemanticColors.muted(context),
          ),
        ),
        label(2, 'Confirm & take payment'),
      ],
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.categories,
    required this.selectedId,
    required this.countFor,
    required this.onChanged,
  });

  final List<Category> categories;
  final int? selectedId;
  final int Function(int? id) countFor;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('All (${countFor(null)})'),
              selected: selectedId == null,
              onSelected: (_) => onChanged(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${category.name} (${countFor(category.id)})'),
                selected: selectedId == category.id,
                onSelected: (_) => onChanged(category.id),
              ),
            ),
        ],
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
        mainAxisExtent: 104,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        final outOfStock = product.stock <= 0;
        final low = !outOfStock && product.stock <= product.reorderLevel;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: outOfStock ? null : () => onTap(product),
            child: Opacity(
              opacity: outOfStock ? 0.5 : 1,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    // One Text rather than a Row: a long price beside a unit
                    // overflows the narrower cells, and this ellipsizes
                    // instead of striping.
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _amountFormat.format(product.sellingPrice),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' / ${product.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              color: SemanticColors.muted(context),
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      outOfStock
                          ? 'Out of stock'
                          : '${_amountFormat.format(product.stock)} ${product.unit}'
                                '${low ? ' · low' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: outOfStock
                            ? SemanticColors.debt(context)
                            : low
                            ? SemanticColors.warning(context)
                            : SemanticColors.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.cart,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.discountController,
    required this.floorFor,
    required this.onDiscountChanged,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemoveLine,
    required this.onHold,
    required this.onReview,
  });

  final List<CartLine> cart;
  final double subtotal;
  final double discount;
  final double total;
  final TextEditingController discountController;

  /// A product's minSellingPrice, so a line can show what it may not go
  /// below. Passed in rather than looked up here: the panel has no business
  /// reading the product table.
  final double Function(int productId) floorFor;

  final ValueChanged<String> onDiscountChanged;
  final void Function(int productId, double quantity) onQuantityChanged;
  final void Function(int productId, double price) onPriceChanged;
  final ValueChanged<int> onRemoveLine;
  final VoidCallback onHold;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // The whole panel scrolls, fixed fields and list together: the
        // fields alone can exceed a short window before the list needs any
        // room at all.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Order',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (cart.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Tap a product to start the order.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: SemanticColors.muted(context),
                          ),
                        ),
                      )
                    else
                      for (final line in cart)
                        _OrderLineRow(
                          key: ValueKey(line.productId),
                          line: line,
                          floor: floorFor(line.productId),
                          onQuantityChanged: (quantity) =>
                              onQuantityChanged(line.productId, quantity),
                          onPriceChanged: (price) =>
                              onPriceChanged(line.productId, price),
                          onRemove: () => onRemoveLine(line.productId),
                        ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: onDiscountChanged,
                      decoration: const InputDecoration(
                        labelText: 'Discount on the whole order',
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            _TotalsRow(label: 'Subtotal', value: subtotal),
            if (discount > 0) _TotalsRow(label: 'Discount', value: -discount),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Order total',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  _amountFormat.format(total),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('Review order'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: cart.isEmpty ? null : onHold,
              child: const Text('Hold order'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of the order, with its price open to negotiation.
///
/// A hardware counter haggles — a plumber taking forty lengths does not pay
/// the shelf price — so the price is a field here rather than a fixed
/// figure. The product's own floor is shown beneath it and the box turns red
/// below that: the sale is refused at that point anyway, and finding out
/// while the order is being built beats finding out at payment.
class _OrderLineRow extends StatefulWidget {
  const _OrderLineRow({
    required this.line,
    required this.floor,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onRemove,
    super.key,
  });

  final CartLine line;

  /// The product's minSellingPrice — the lowest this line may go.
  final double floor;

  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onPriceChanged;
  final VoidCallback onRemove;

  @override
  State<_OrderLineRow> createState() => _OrderLineRowState();
}

class _OrderLineRowState extends State<_OrderLineRow> {
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: widget.line.price.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(_OrderLineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the model when something else moved the price — resuming a held
    // order, say — but never while this box is the thing being typed in.
    if (double.tryParse(_price.text) != widget.line.price) {
      _price.text = widget.line.price.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final belowFloor = line.price < widget.floor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null) widget.onPriceChanged(parsed);
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Unit price',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      errorText: belowFloor
                          ? 'Min ${_amountFormat.format(widget.floor)}'
                          : null,
                      errorStyle: const TextStyle(fontSize: 10),
                      helperText: belowFloor
                          ? null
                          : 'Min ${_amountFormat.format(widget.floor)}',
                      helperStyle: TextStyle(
                        fontSize: 10,
                        color: SemanticColors.muted(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.remove, size: 16),
                      tooltip: 'One fewer',
                      onPressed: () => widget.onQuantityChanged(line.quantity - 1),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        _amountFormat.format(line.quantity),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.add, size: 16),
                      tooltip: 'One more',
                      onPressed: () => widget.onQuantityChanged(line.quantity + 1),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Remove',
                      onPressed: widget.onRemove,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            _amountFormat.format(line.lineTotal),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: SemanticColors.muted(context),
              fontSize: 13,
            ),
          ),
          Text(
            _amountFormat.format(value),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
