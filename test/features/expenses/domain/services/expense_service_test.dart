import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:duka_pos/features/expenses/domain/services/expense_service.dart';
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
  late ExpenseRepositoryImpl repository;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = ExpenseRepositoryImpl(db);
  });

  tearDown(() => db.close());

  ExpenseService serviceAs(String role) {
    return ExpenseService(repository, AuthorizationService(_userWithRole(role)));
  }

  test('a cashier cannot addExpense', () {
    expect(
      () => serviceAs(
        'cashier',
      ).addExpense(category: 'Rent', description: 'April rent', amount: 5000),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('a manager can addExpense', () async {
    final expense = await serviceAs(
      'manager',
    ).addExpense(category: 'Rent', description: 'April rent', amount: 5000);

    expect(expense.category, 'Rent');
    expect(expense.amount, 5000);

    final reloaded = await repository.watchExpenses().first;
    expect(reloaded, hasLength(1));
  });

  test('an admin can addExpense', () async {
    final expense = await serviceAs(
      'admin',
    ).addExpense(category: 'Utilities', description: 'Electricity bill', amount: 1200);

    expect(expense.category, 'Utilities');
  });
}
