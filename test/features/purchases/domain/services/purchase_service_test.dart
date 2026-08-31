import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:duka_pos/features/purchases/domain/services/purchase_service.dart';
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
  late PurchaseRepositoryImpl repository;
  late int productId;
  late int supplierId;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = PurchaseRepositoryImpl(db, StockMovementRepositoryImpl(db));

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        createdAt: DateTime.now(),
      ),
    )).id;
    supplierId = (await db.into(db.suppliers).insertReturning(
      SuppliersCompanion.insert(
        uuid: 'sup-1',
        name: 'Acme',
        createdAt: DateTime.now(),
      ),
    )).id;
    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'manager',
        passwordHash: 'hash',
        fullName: 'Manager One',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  PurchaseService serviceAs(String role) {
    return PurchaseService(repository, AuthorizationService(_userWithRole(role)));
  }

  List<PurchaseItemsCompanion> items() => [
    PurchaseItemsCompanion.insert(
      uuid: 'item-placeholder',
      purchaseId: 0,
      productId: productId,
      quantity: 10,
      unitCost: 30,
      total: 300,
      createdAt: DateTime.now(),
    ),
  ];

  test('cashier cannot receiveStock', () {
    expect(
      () => serviceAs('cashier').receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: items(),
        paymentStatus: 'paid',
        amountPaid: 300,
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('manager can receiveStock', () async {
    final purchase = await serviceAs('manager').receiveStock(
      supplierId: supplierId,
      userId: userId,
      items: items(),
      paymentStatus: 'paid',
      amountPaid: 300,
    );

    expect(purchase.status, 'received');
  });
}
