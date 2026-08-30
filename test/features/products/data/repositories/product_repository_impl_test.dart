import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/data/repositories/product_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late ProductRepositoryImpl repo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = ProductRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<Product> addProduct({double stock = 0, double reorderLevel = 0}) {
    return repo.addProduct(
      name: 'Soda',
      costPrice: 50,
      sellingPrice: 80,
      minSellingPrice: 60,
      stock: stock,
      reorderLevel: reorderLevel,
    );
  }

  test('deleteProduct soft-deletes: row still readable, dropped from watchProducts', () async {
    final product = await addProduct();
    await repo.deleteProduct(product.uuid);

    final stillFound = await repo.getProductByUuid(product.uuid);
    expect(stillFound?.isActive, isFalse);

    final active = await repo.watchProducts().first;
    expect(active, isEmpty);
  });

  test('watchLowStockProducts only returns products at or below reorderLevel', () async {
    await addProduct(stock: 10, reorderLevel: 5);
    final low = await addProduct(stock: 2, reorderLevel: 5);

    final results = await repo.watchLowStockProducts().first;
    expect(results.map((p) => p.uuid), [low.uuid]);
  });

  test('adjustStock applies a signed delta', () async {
    final product = await addProduct(stock: 10);

    await repo.adjustStock(productUuid: product.uuid, quantityChange: -3);
    var updated = await repo.getProductByUuid(product.uuid);
    expect(updated?.stock, 7);

    await repo.adjustStock(productUuid: product.uuid, quantityChange: 5);
    updated = await repo.getProductByUuid(product.uuid);
    expect(updated?.stock, 12);
  });

  test('getProductByBarcode finds a matching product', () async {
    await repo.addProduct(
      name: 'Bread',
      barcode: '12345',
      costPrice: 40,
      sellingPrice: 60,
      minSellingPrice: 45,
    );

    final found = await repo.getProductByBarcode('12345');
    expect(found?.name, 'Bread');
  });
}
