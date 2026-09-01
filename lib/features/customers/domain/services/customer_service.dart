import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/domain/exceptions.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_repository.dart';

/// Application-layer entry point for customer writes: enforces
/// [Permission.manageCustomers] and protects the seeded walk-in customer
/// (see [Customer.isWalkIn]) from edits, in front of [CustomerRepository],
/// which stays a plain data-access boundary. watchCustomers passes straight
/// through — a cashier picking a customer for a credit sale needs to read
/// the list too; only mutating it is gated.
///
/// There is deliberately no way to create another walk-in row through this
/// service — [addCustomer] never exposes [isWalkIn], so seeding
/// (seedWalkInCustomer) is the only path that ever sets it.
class CustomerService {
  CustomerService(this._repository, this._authorizationService);

  final CustomerRepository _repository;
  final AuthorizationService _authorizationService;

  Stream<List<Customer>> watchCustomers() => _repository.watchCustomers();

  Future<Customer> addCustomer({
    required String name,
    String? phone,
    String? email,
    String? address,
    double creditLimit = 0,
  }) {
    _authorizationService.require(Permission.manageCustomers);
    return _repository.addCustomer(
      name: name,
      phone: phone,
      email: email,
      address: address,
      creditLimit: creditLimit,
    );
  }

  Future<void> updateCustomer(Customer customer) {
    _authorizationService.require(Permission.manageCustomers);
    if (customer.isWalkIn) {
      throw const WalkInCustomerNotEditableException();
    }
    return _repository.updateCustomer(customer);
  }
}
