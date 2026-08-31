import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final productSearchQueryProvider = StateProvider<String>((ref) => '');

/// null means "all categories".
final productCategoryFilterProvider = StateProvider<int?>((ref) => null);

final productLowStockOnlyProvider = StateProvider<bool>((ref) => false);

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).watchCategories();
});

final _productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchProducts();
});

/// [_productsStreamProvider] filtered by search text (matches name, SKU or
/// barcode), category and low-stock-only — recombined client-side on every
/// change to the product list or any filter, since the catalog is small
/// enough that this beats adding a bespoke SQL query per filter
/// combination.
final filteredProductsProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final productsAsync = ref.watch(_productsStreamProvider);
  final query = ref.watch(productSearchQueryProvider).trim().toLowerCase();
  final categoryId = ref.watch(productCategoryFilterProvider);
  final lowStockOnly = ref.watch(productLowStockOnlyProvider);

  return productsAsync.whenData((products) {
    return products.where((product) {
      if (categoryId != null && product.categoryId != categoryId) {
        return false;
      }
      if (lowStockOnly && product.stock > product.reorderLevel) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [
          product.name,
          product.sku ?? '',
          product.barcode ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  });
});
