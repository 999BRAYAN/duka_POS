import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/products/presentation/screens/product_form_screen.dart';
import 'package:duka_pos/features/sales/presentation/screens/sale_screen.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _priceFormat = NumberFormat('#,##0.00');

/// Product catalog for a desktop browser window: a dense, searchable,
/// filterable data table rather than a mobile card-per-item list.
class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(productSearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    final categoryById = {for (final c in categories) c.id: c};
    final canManageProducts = ref
        .watch(authorizationServiceProvider)
        .can(Permission.manageProducts);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        // Navigation lives in the drawer now, so this bar carries only what
        // belongs to this screen. It had overflowed twice as screens were
        // added, and a hamburger scales where a row of buttons does not.
        actions: [
          if (canManageProducts)
            IconButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProductFormScreen()),
              ),
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Add product',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SaleScreen()),
              ),
              icon: const Icon(Icons.point_of_sale, size: 18),
              label: const Text('New sale'),
            ),
          ),
        ],
      ),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'products'),
      body: NavRail(destination: 'products', child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FilterBar(searchController: _searchController, categories: categories),
            const SizedBox(height: 16),
            Expanded(
              child: productsAsync.when(
                data: (products) => products.isEmpty
                    ? const _EmptyState()
                    : _ProductTable(
                        products: products,
                        categoryById: categoryById,
                        canManage: canManageProducts,
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Failed to load products: $error')),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.searchController, required this.categories});

  final TextEditingController searchController;
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryFilter = ref.watch(productCategoryFilterProvider);
    final lowStockOnly = ref.watch(productLowStockOnlyProvider);

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
                ref.read(productSearchQueryProvider.notifier).state = value,
            decoration: const InputDecoration(
              hintText: 'Search by name, SKU or barcode',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int?>(
            initialValue: categoryFilter,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('All categories')),
              for (final category in categories)
                DropdownMenuItem(value: category.id, child: Text(category.name)),
            ],
            onChanged: (value) =>
                ref.read(productCategoryFilterProvider.notifier).state = value,
          ),
        ),
        FilterChip(
          label: const Text('Low stock only'),
          selected: lowStockOnly,
          onSelected: (selected) =>
              ref.read(productLowStockOnlyProvider.notifier).state = selected,
        ),
      ],
    );
  }
}

class _ProductTable extends StatelessWidget {
  const _ProductTable({
    required this.products,
    required this.categoryById,
    required this.canManage,
  });

  final List<Product> products;
  final Map<int, Category> categoryById;
  final bool canManage;

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
              const DataColumn(label: Text('Name')),
              const DataColumn(label: Text('SKU')),
              const DataColumn(label: Text('Category')),
              const DataColumn(label: Text('Stock'), numeric: true),
              const DataColumn(label: Text('Cost'), numeric: true),
              const DataColumn(label: Text('Price'), numeric: true),
              if (canManage) const DataColumn(label: Text('')),
            ],
            rows: [for (final product in products) _row(context, product)],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, Product product) {
    final isLowStock = product.stock <= product.reorderLevel;
    final category = categoryById[product.categoryId];

    return DataRow(
      color: isLowStock
          ? WidgetStatePropertyAll(SemanticColors.warningSurface(context))
          : null,
      cells: [
        DataCell(Text(product.name)),
        DataCell(Text(product.sku ?? '—')),
        DataCell(Text(category?.name ?? '—')),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_priceFormat.format(product.stock)),
              if (isLowStock) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: SemanticColors.warning(context),
                ),
              ],
            ],
          ),
        ),
        DataCell(Text(_priceFormat.format(product.costPrice))),
        DataCell(Text(_priceFormat.format(product.sellingPrice))),
        if (canManage)
          DataCell(
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductFormScreen(product: product),
                ),
              ),
              child: const Text('Edit'),
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
      child: Text(
        'No products match your filters.',
        style: TextStyle(color: AppColors.stone500),
      ),
    );
  }
}
