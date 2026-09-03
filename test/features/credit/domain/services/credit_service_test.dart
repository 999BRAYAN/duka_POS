import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/credit/domain/services/credit_service.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
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
  late CreditRepositoryImpl repository;
  late int customerId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = CreditRepositoryImpl(db);

    customerId = (await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(uuid: 'cust-1', name: 'Jane Doe', createdAt: DateTime.now()),
    )).id;

    await repository.chargeCustomer(customerId: customerId, amount: 500);
  });

  tearDown(() => db.close());

  CreditService serviceAs(String role) {
    // CreditService now depends on SaleRepository (see its class doc for
    // why), which itself needs the other two repositories a completed sale
    // touches — unused by these tests beyond satisfying the constructor.
    final saleRepository = SaleRepositoryImpl(
      db,
      StockMovementRepositoryImpl(db),
      repository,
    );
    return CreditService(saleRepository, AuthorizationService(_userWithRole(role)));
  }

  test('a cashier cannot recordPayment', () {
    expect(
      () => serviceAs('cashier').recordPayment(customerId: customerId, amount: 200, method: 'cash'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('a manager can recordPayment', () async {
    final txn = await serviceAs(
      'manager',
    ).recordPayment(customerId: customerId, amount: 200, method: 'cash');

    expect(txn.type, 'PAYMENT');
    expect(txn.balanceAfter, 300);
  });

  test('an admin can recordPayment', () async {
    final txn = await serviceAs(
      'admin',
    ).recordPayment(customerId: customerId, amount: 200, method: 'mpesa');

    expect(txn.method, 'mpesa');
  });
}
