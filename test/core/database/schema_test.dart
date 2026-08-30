import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

const _expectedTables = {
  'users',
  'categories',
  'products',
  'customers',
  'suppliers',
  'stock_movements',
  'sales',
  'sale_items',
  'purchases',
  'purchase_items',
  'credit_transactions',
  'expenses',
};

void main() {
  late DukaDatabase db;

  setUp(() {
    db = DukaDatabase.forTesting(
      NativeDatabase.memory(setup: enableForeignKeys),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('all 12 tables are created', () async {
    expect(db.allTables, hasLength(12));

    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final actualTableNames = rows.map((r) => r.read<String>('name')).toSet();

    expect(
      actualTableNames.containsAll(_expectedTables),
      isTrue,
      reason: 'missing tables: ${_expectedTables.difference(actualTableNames)}',
    );
  });

  group('Products <-> StockMovements foreign key', () {
    test('a stock movement can reference an existing product', () async {
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              uuid: 'product-1',
              name: 'Sugar 1kg',
              createdAt: DateTime.now(),
            ),
          );

      final movementId = await db
          .into(db.stockMovements)
          .insert(
            StockMovementsCompanion.insert(
              uuid: 'movement-1',
              productId: productId,
              type: 'IN',
              quantity: 10,
              createdAt: DateTime.now(),
            ),
          );

      final movements = await db.select(db.stockMovements).get();
      expect(movements, hasLength(1));
      expect(movements.single.id, movementId);
      expect(movements.single.productId, productId);
    });

    test(
      'a stock movement referencing a non-existent product is rejected',
      () async {
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                uuid: 'product-2',
                name: 'Rice 2kg',
                createdAt: DateTime.now(),
              ),
            );
        final nonExistentProductId = productId + 999;

        await expectLater(
          db
              .into(db.stockMovements)
              .insert(
                StockMovementsCompanion.insert(
                  uuid: 'movement-2',
                  productId: nonExistentProductId,
                  type: 'IN',
                  quantity: 1,
                  createdAt: DateTime.now(),
                ),
              ),
          throwsA(isA<SqliteException>()),
        );

        // Nothing should have been written.
        expect(await db.select(db.stockMovements).get(), isEmpty);
      },
    );
  });
}
