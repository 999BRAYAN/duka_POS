import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Product] rows — deliberately has no
/// stock-adjusting method. Stock changes go through
/// StockMovementRepository.recordMovement (or InventoryService.adjustStock
/// for a manual correction) instead, so every change to [Product.stock] is
/// backed by a StockMovement audit row.
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
}
