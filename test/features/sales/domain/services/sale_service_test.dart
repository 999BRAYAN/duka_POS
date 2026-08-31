import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/domain/services/sale_service.dart';
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
  late SaleRepositoryImpl repository;
  late int productId;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = SaleRepositoryImpl(db, StockMovementRepositoryImpl(db));

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(10),
        createdAt: DateTime.now(),
      ),
    )).id;
    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  SaleService serviceAs(String role) {
    return SaleService(repository, AuthorizationService(_userWithRole(role)));
  }

  test('a signed-out user cannot completeSale', () {
    expect(
      () => SaleService(repository, const AuthorizationService(null)).completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 70,
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('a cashier can completeSale', () async {
    final sale = await serviceAs('cashier').completeSale(
      cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
      userId: userId,
      paymentMethod: 'cash',
      amountPaid: 70,
    );

    expect(sale.total, 70);
  });

  test('a manager can completeSale', () async {
    final sale = await serviceAs('manager').completeSale(
      cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
      userId: userId,
      paymentMethod: 'cash',
      amountPaid: 70,
    );

    expect(sale.total, 70);
  });
}
