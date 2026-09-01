import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late CreditRepositoryImpl repo;
  late int customerId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CreditRepositoryImpl(db);

    customerId = (await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane Doe',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  test('chargeCustomer increases balance and records a CHARGE transaction', () async {
    final txn = await repo.chargeCustomer(customerId: customerId, amount: 500);

    expect(txn.type, 'CHARGE');
    expect(txn.balanceAfter, 500);
    expect(await repo.getCustomerBalance(customerId), 500);
  });

  test('recordPayment decreases balance and records a PAYMENT transaction', () async {
    await repo.chargeCustomer(customerId: customerId, amount: 500);
    final txn = await repo.recordPayment(customerId: customerId, amount: 200, method: 'cash');

    expect(txn.type, 'PAYMENT');
    expect(txn.method, 'cash');
    expect(txn.balanceAfter, 300);
    expect(await repo.getCustomerBalance(customerId), 300);
  });

  test('recordPayment never takes the balance below zero', () async {
    await repo.chargeCustomer(customerId: customerId, amount: 200);
    final txn = await repo.recordPayment(customerId: customerId, amount: 500, method: 'cash');

    expect(txn.balanceAfter, 0);
    expect(await repo.getCustomerBalance(customerId), 0);
  });

  test('chargeCustomer records no payment method', () async {
    final txn = await repo.chargeCustomer(customerId: customerId, amount: 500);
    expect(txn.method, isNull);
  });

  test('watchTransactionsForCustomer returns newest first', () async {
    await repo.chargeCustomer(customerId: customerId, amount: 500);
    await repo.recordPayment(customerId: customerId, amount: 200, method: 'cash');

    final transactions = await repo.watchTransactionsForCustomer(customerId).first;
    expect(transactions.map((t) => t.type), ['PAYMENT', 'CHARGE']);
  });
}
