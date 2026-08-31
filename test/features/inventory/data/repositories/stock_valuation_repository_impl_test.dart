import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_valuation_repository_impl.dart';
import 'package:duka_pos/features/products/data/repositories/product_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late StockValuationRepositoryImpl valuationRepo;
  late StockMovementRepositoryImpl movementRepo;
  late ProductRepositoryImpl productRepo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    valuationRepo = StockValuationRepositoryImpl(db);
    movementRepo = StockMovementRepositoryImpl(db);
    productRepo = ProductRepositoryImpl(db);
  });

  tearDown(() => db.close());

  Future<Product> addProduct({
    required String name,
    double costPrice = 0,
    double reorderLevel = 0,
  }) {
    return productRepo.addProduct(
      name: name,
      costPrice: costPrice,
      sellingPrice: costPrice,
      minSellingPrice: costPrice,
      reorderLevel: reorderLevel,
    );
  }

  test('falls back to Product.costPrice when there is no purchase history', () async {
    await addProduct(name: 'Soda', costPrice: 10, reorderLevel: 5);

    final valuation = (await valuationRepo.watchStockValuation().first).single;
    expect(valuation.stock, 0);
    expect(valuation.averageCost, 10);
    expect(valuation.stockValue, 0);
    expect(valuation.isLowStock, isTrue); // 0 <= 5
  });

  test('averageCost is the quantity-weighted average of PURCHASE movements', () async {
    final product = await addProduct(name: 'Rice', costPrice: 99, reorderLevel: 5);

    await movementRepo.recordMovement(
      productId: product.id,
      type: 'PURCHASE',
      quantity: 10,
      unitCost: 20,
    );
    await movementRepo.recordMovement(
      productId: product.id,
      type: 'PURCHASE',
      quantity: 10,
      unitCost: 30,
    );

    final valuation = (await valuationRepo.watchStockValuation().first).single;
    expect(valuation.stock, 20);
    expect(valuation.averageCost, 25); // (10*20 + 10*30) / 20
    expect(valuation.stockValue, 500);
    expect(valuation.isLowStock, isFalse);
  });

  test('RETURN movements affect stock but not averageCost', () async {
    final product = await addProduct(name: 'Rice', costPrice: 99, reorderLevel: 5);

    await movementRepo.recordMovement(
      productId: product.id,
      type: 'PURCHASE',
      quantity: 10,
      unitCost: 20,
    );
    await movementRepo.recordMovement(
      productId: product.id,
      type: 'RETURN',
      quantity: 5,
      unitCost: 999,
    );

    final valuation = (await valuationRepo.watchStockValuation().first).single;
    expect(valuation.stock, 15);
    expect(valuation.averageCost, 20); // unaffected by the RETURN's unitCost
  });

  test('isLowStock is true when stock exactly equals reorderLevel', () async {
    final product = await addProduct(name: 'Salt', reorderLevel: 5);
    await movementRepo.recordMovement(productId: product.id, type: 'ADJUSTMENT', quantity: 5);

    final valuation = (await valuationRepo.watchStockValuation().first).single;
    expect(valuation.stock, 5);
    expect(valuation.isLowStock, isTrue);
  });

  test('deactivated products are excluded', () async {
    final product = await addProduct(name: 'Discontinued');
    await productRepo.deleteProduct(product.uuid);

    final valuations = await valuationRepo.watchStockValuation().first;
    expect(valuations, isEmpty);
  });

  test('results are ordered by name', () async {
    await addProduct(name: 'Zebra soap');
    await addProduct(name: 'Apple juice');

    final valuations = await valuationRepo.watchStockValuation().first;
    expect(valuations.map((v) => v.name), ['Apple juice', 'Zebra soap']);
  });
}
