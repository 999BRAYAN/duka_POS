import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/domain/exceptions.dart';
import 'package:duka_pos/features/inventory/domain/services/inventory_service.dart';
import 'package:flutter_test/flutter_test.dart';

User _userWithRole(String role) {
  return User(
    id: 1,
    uuid: 'u1',
    username: 'jdoe',
    passwordHash: 'hash',
    fullName: 'Jane Doe',
    role: role,
    isActive: true,
    createdAt: DateTime(2026),
  );
}

void main() {
  late DukaDatabase db;
  late StockMovementRepositoryImpl stockMovements;
  late int productId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    stockMovements = StockMovementRepositoryImpl(db);

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

  InventoryService serviceAs(String role) {
    return InventoryService(stockMovements, AuthorizationService(_userWithRole(role)));
  }

  test('cashier cannot adjustStock', () {
    expect(
      () => serviceAs('cashier').adjustStock(
        productId: productId,
        quantityChange: 5,
        reason: 'Stock count correction',
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('manager can adjustStock with a reason, and it updates Products.stock', () async {
    await serviceAs('manager').adjustStock(
      productId: productId,
      quantityChange: -2,
      reason: 'Damaged in storage',
    );

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 8);

    final movements = await stockMovements.watchMovementsForProduct(productId).first;
    expect(movements.single.type, 'ADJUSTMENT');
    expect(movements.single.notes, 'Damaged in storage');
  });

  test('adjustStock rejects an empty reason', () {
    expect(
      () => serviceAs('manager').adjustStock(
        productId: productId,
        quantityChange: -2,
        reason: '   ',
      ),
      throwsA(isA<MissingAdjustmentReasonException>()),
    );
  });

  test('authorization is checked before the reason is validated', () {
    expect(
      () => serviceAs('cashier').adjustStock(
        productId: productId,
        quantityChange: -2,
        reason: '',
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}
