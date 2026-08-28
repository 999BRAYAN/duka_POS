import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Customer] rows.
abstract interface class CustomerRepository {
  Future<Customer> addCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    double creditLimit,
  });

  Future<void> updateCustomer(Customer customer);

  Future<void> deleteCustomer(String uuid);

  Future<Customer?> getCustomerByUuid(String uuid);

  Stream<List<Customer>> watchCustomers();

  Stream<List<Customer>> watchCustomersWithOutstandingBalance();
}
