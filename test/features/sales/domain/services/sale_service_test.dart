import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
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
    repository = SaleRepositoryImpl(
      db,
      StockMovementRepositoryImpl(db),
      CreditRepositoryImpl(db),
    );

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

  group('overrideCreditLimit', () {
    Future<int> addOverLimitCustomer() {
      return db
          .into(db.customers)
          .insertReturning(
            CustomersCompanion.insert(
              uuid: 'cust-1',
              name: 'Jane',
              creditLimit: const Value(100),
              currentBalance: const Value(80),
              createdAt: DateTime.now(),
            ),
          )
          .then((c) => c.id);
    }

    test('a cashier cannot pass overrideCreditLimit, even to complete their own sale', () async {
      final customerId = await addOverLimitCustomer();

      expect(
        () => serviceAs('cashier').completeSale(
          cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
          customerId: customerId,
          userId: userId,
          paymentMethod: 'credit',
          overrideCreditLimit: true,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('a manager can pass overrideCreditLimit to bypass the limit check', () async {
      final customerId = await addOverLimitCustomer();

      final sale = await serviceAs('manager').completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        overrideCreditLimit: true,
      );

      expect(sale.total, 70);
    });

    test('overrideCreditLimit permission is not required when left false', () async {
      final customerId = await addOverLimitCustomer();

      // Cashiers may still complete ordinary sales for this customer —
      // they just can't push it over the limit.
      final sale = await serviceAs('cashier').completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 70, quantity: 1)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 70,
      );

      expect(sale.total, 70);
    });
  });
}
