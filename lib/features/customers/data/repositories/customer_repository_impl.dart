import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_repository.dart';
import 'package:uuid/uuid.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Customer> addCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    double creditLimit = 0,
  }) {
    return _db.into(_db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: _uuid.v4(),
        name: name,
        phone: Value(phone),
        email: Value(email),
        address: Value(address),
        creditLimit: Value(creditLimit),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateCustomer(Customer customer) {
    return _db
        .update(_db.customers)
        .replace(customer.copyWith(updatedAt: Value(DateTime.now())));
  }

  @override
  Future<void> deleteCustomer(String uuid) {
    return (_db.delete(
      _db.customers,
    )..where((t) => t.uuid.equals(uuid))).go();
  }

  @override
  Future<Customer?> getCustomerByUuid(String uuid) {
    return (_db.select(
      _db.customers,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Stream<List<Customer>> watchCustomers() {
    return (_db.select(_db.customers)..orderBy([
      (t) => OrderingTerm(expression: t.name),
    ])).watch();
  }

  @override
  Stream<List<Customer>> watchCustomersWithOutstandingBalance() {
    return (_db.select(_db.customers)
          ..where((t) => t.currentBalance.isBiggerThanValue(0))
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }
}
