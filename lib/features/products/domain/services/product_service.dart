import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/domain/exceptions.dart';
import 'package:duka_pos/features/products/domain/repositories/product_repository.dart';

/// Application-layer entry point for product writes: enforces
/// [Permission.manageProducts] and the min-selling-price-vs-cost rule in
/// front of [ProductRepository], which stays a plain data-access boundary.
/// Reads (watchProducts) pass straight through — every role may view the
/// catalog, only mutating it is gated.
class ProductService {
  ProductService(this._repository, this._authorizationService);

  final ProductRepository _repository;
  final AuthorizationService _authorizationService;

  Stream<List<Product>> watchProducts() => _repository.watchProducts();

  /// Set [confirmPriceBelowCost] only after the user has explicitly
  /// confirmed selling below cost (e.g. via a confirmation dialog) —
  /// otherwise a [minSellingPrice] below [costPrice] throws
  /// [PriceBelowCostException] instead of saving.
  Future<Product> addProduct({
    required String name,
    String? sku,
    String? barcode,
    String? description,
    int? categoryId,
    String unit = 'pcs',
    required double costPrice,
    required double sellingPrice,
    required double minSellingPrice,
    double stock = 0,
    double reorderLevel = 0,
    bool confirmPriceBelowCost = false,
  }) {
    _authorizationService.require(Permission.manageProducts);
    _validatePrice(
      costPrice: costPrice,
      minSellingPrice: minSellingPrice,
      confirmed: confirmPriceBelowCost,
    );
    return _repository.addProduct(
      name: name,
      sku: sku,
      barcode: barcode,
      description: description,
      categoryId: categoryId,
      unit: unit,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      minSellingPrice: minSellingPrice,
      stock: stock,
      reorderLevel: reorderLevel,
    );
  }

  /// See [addProduct] for [confirmPriceBelowCost].
  Future<void> updateProduct(
    Product product, {
    bool confirmPriceBelowCost = false,
  }) {
    _authorizationService.require(Permission.manageProducts);
    _validatePrice(
      costPrice: product.costPrice,
      minSellingPrice: product.minSellingPrice,
      confirmed: confirmPriceBelowCost,
    );
    return _repository.updateProduct(product);
  }

  Future<void> deactivateProduct(String uuid) {
    _authorizationService.require(Permission.manageProducts);
    return _repository.deleteProduct(uuid);
  }

  void _validatePrice({
    required double costPrice,
    required double minSellingPrice,
    required bool confirmed,
  }) {
    if (minSellingPrice < costPrice && !confirmed) {
      throw PriceBelowCostException(
        costPrice: costPrice,
        minSellingPrice: minSellingPrice,
      );
    }
  }
}
