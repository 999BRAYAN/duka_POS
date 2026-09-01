import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:duka_pos/features/customers/domain/exceptions.dart';
import 'package:duka_pos/features/customers/domain/services/customer_service.dart';
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
  late CustomerRepositoryImpl repository;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = CustomerRepositoryImpl(db);
  });

  tearDown(() => db.close());

  CustomerService serviceAs(String role) {
    return CustomerService(repository, AuthorizationService(_userWithRole(role)));
  }

  group('authorization', () {
    test('cashier cannot addCustomer', () {
      expect(
        () => serviceAs('cashier').addCustomer(name: 'Jane Doe'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('cashier cannot updateCustomer', () async {
      final customer = await serviceAs('manager').addCustomer(name: 'Jane Doe');

      expect(
        () => serviceAs('cashier').updateCustomer(customer.copyWith(name: 'Jane R. Doe')),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('manager can addCustomer and updateCustomer', () async {
      final customer = await serviceAs('manager').addCustomer(name: 'Jane Doe', creditLimit: 500);
      expect(customer.name, 'Jane Doe');
      expect(customer.creditLimit, 500);

      await serviceAs('manager').updateCustomer(customer.copyWith(name: 'Jane R. Doe'));
      final reloaded = await repository.getCustomerByUuid(customer.uuid);
      expect(reloaded?.name, 'Jane R. Doe');
    });
  });

  test('watchCustomers requires no permission', () async {
    await serviceAs('manager').addCustomer(name: 'Jane Doe');
    final customers = await serviceAs('cashier').watchCustomers().first;
    expect(customers.map((c) => c.name), ['Jane Doe']);
  });

  group('the walk-in customer', () {
    Future<Customer> insertWalkIn() {
      return db.into(db.customers).insertReturning(
        CustomersCompanion.insert(
          uuid: 'walk-in',
          name: 'Walk-in Customer',
          creditLimit: const Value(0),
          isWalkIn: const Value(true),
          createdAt: DateTime.now(),
        ),
      );
    }

    test('cannot be edited even by a manager', () async {
      final walkIn = await insertWalkIn();

      expect(
        () => serviceAs('manager').updateCustomer(walkIn.copyWith(name: 'Renamed')),
        throwsA(isA<WalkInCustomerNotEditableException>()),
      );

      final reloaded = await repository.getCustomerByUuid(walkIn.uuid);
      expect(reloaded?.name, 'Walk-in Customer');
    });

    test('authorization is still checked first for a cashier', () {
      // A cashier trying to edit the walk-in row should see the permission
      // error, not the walk-in-specific one — auth is the outer gate.
      final walkIn = Customer(
        id: 1,
        uuid: 'walk-in',
        name: 'Walk-in Customer',
        creditLimit: 0,
        currentBalance: 0,
        isWalkIn: true,
        createdAt: DateTime(2026),
      );

      expect(
        () => serviceAs('cashier').updateCustomer(walkIn.copyWith(name: 'Renamed')),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });
}
