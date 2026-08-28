import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Product] rows. No implementation yet —
/// this is the boundary that keeps Drift/SQL details out of the UI layer.
abstract interface class ProductRepository {
  Future<Product> addProduct({
    required String name,
    String? sku,
    String? barcode,
    String? description,
    int? categoryId,
    String unit,
    required double costPrice,
    required double sellingPrice,
    required double minSellingPrice,
    double stock,
    double reorderLevel,
  });

  Future<void> updateProduct(Product product);

  Future<void> deleteProduct(String uuid);

  Future<Product?> getProductByUuid(String uuid);

  Future<Product?> getProductByBarcode(String barcode);

  Stream<List<Product>> watchProducts();

  Stream<List<Product>> watchProductsByCategory(int categoryId);

  Stream<List<Product>> watchLowStockProducts();

  /// Applies a signed delta to a product's stock (positive to add, negative
  /// to remove). Callers are expected to also write a matching
  /// [StockMovement] via the inventory repository.
  Future<void> adjustStock({
    required String productUuid,
    required double quantityChange,
  });
}
