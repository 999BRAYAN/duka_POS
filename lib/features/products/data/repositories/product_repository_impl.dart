import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/domain/repositories/product_repository.dart';
import 'package:uuid/uuid.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
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
  }) {
    return _db.into(_db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: _uuid.v4(),
        sku: Value(sku),
        barcode: Value(barcode),
        name: name,
        description: Value(description),
        categoryId: Value(categoryId),
        unit: Value(unit),
        costPrice: Value(costPrice),
        sellingPrice: Value(sellingPrice),
        minSellingPrice: Value(minSellingPrice),
        stock: Value(stock),
        reorderLevel: Value(reorderLevel),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateProduct(Product product) {
    return _db
        .update(_db.products)
        .replace(product.copyWith(updatedAt: Value(DateTime.now())));
  }

  // Products can be referenced by sale items, purchase items and stock
  // movements, so this is a soft delete via `isActive` rather than a row
  // DELETE (which would fail its foreign key constraints once referenced).
  @override
  Future<void> deleteProduct(String uuid) {
    return (_db.update(_db.products)..where((t) => t.uuid.equals(uuid))).write(
      ProductsCompanion(
        isActive: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<Product?> getProductByUuid(String uuid) {
    return (_db.select(
      _db.products,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Future<Product?> getProductByBarcode(String barcode) {
    return (_db.select(
      _db.products,
    )..where((t) => t.barcode.equals(barcode))).getSingleOrNull();
  }

  @override
  Stream<List<Product>> watchProducts() {
    return (_db.select(_db.products)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  @override
  Stream<List<Product>> watchProductsByCategory(int categoryId) {
    return (_db.select(_db.products)
          ..where(
            (t) => t.categoryId.equals(categoryId) & t.isActive.equals(true),
          )
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  @override
  Stream<List<Product>> watchLowStockProducts() {
    return (_db.select(_db.products)..where(
          (t) =>
              t.isActive.equals(true) &
              t.stock.isSmallerOrEqual(t.reorderLevel),
        ))
        .watch();
  }
}
