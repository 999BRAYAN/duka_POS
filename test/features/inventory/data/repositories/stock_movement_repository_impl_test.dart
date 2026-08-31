import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late StockMovementRepositoryImpl repo;
  late int productId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = StockMovementRepositoryImpl(db);

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(10),
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  test('recordMovement then watchMovementsForProduct returns it', () async {
    await repo.recordMovement(
      productId: productId,
      type: 'ADJUSTMENT',
      quantity: 5,
      notes: 'Stock count correction',
    );

    final movements = await repo.watchMovementsForProduct(productId).first;
    expect(movements, hasLength(1));
    expect(movements.single.type, 'ADJUSTMENT');
    expect(movements.single.notes, 'Stock count correction');
  });

  test('recordMovement applies the signed quantity to Products.stock', () async {
    await repo.recordMovement(productId: productId, type: 'ADJUSTMENT', quantity: 5);
    var product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 15);

    await repo.recordMovement(productId: productId, type: 'SALE', quantity: -3);
    product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 12);
  });

  test('recordMovement persists unitCost when given', () async {
    final movement = await repo.recordMovement(
      productId: productId,
      type: 'PURCHASE',
      quantity: 5,
      unitCost: 42.5,
    );
    expect(movement.unitCost, 42.5);
  });

  test('watchRecentMovements respects the limit and orders newest first', () async {
    for (var i = 0; i < 5; i++) {
      await repo.recordMovement(
        productId: productId,
        type: 'ADJUSTMENT',
        quantity: i.toDouble(),
      );
    }

    final recent = await repo.watchRecentMovements(limit: 3).first;
    expect(recent, hasLength(3));
    expect(recent.first.quantity, 4);
  });
}
