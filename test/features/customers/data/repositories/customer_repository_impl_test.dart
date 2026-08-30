import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late CustomerRepositoryImpl repo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CustomerRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('addCustomer defaults creditLimit and currentBalance to zero', () async {
    final customer = await repo.addCustomer(name: 'Jane Doe');

    expect(customer.creditLimit, 0);
    expect(customer.currentBalance, 0);
  });

  test('deleteCustomer removes the row', () async {
    final customer = await repo.addCustomer(name: 'Jane Doe');
    await repo.deleteCustomer(customer.uuid);

    expect(await repo.getCustomerByUuid(customer.uuid), isNull);
  });

  test('watchCustomersWithOutstandingBalance filters out zero-balance customers', () async {
    final withBalance = await repo.addCustomer(name: 'Owes Money');
    await repo.addCustomer(name: 'Paid Up');
    await repo.updateCustomer(withBalance.copyWith(currentBalance: 500));

    final outstanding = await repo.watchCustomersWithOutstandingBalance().first;
    expect(outstanding.map((c) => c.name), ['Owes Money']);
  });
}
