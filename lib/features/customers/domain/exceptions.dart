/// Thrown by [CustomerService.updateCustomer] when the caller tries to edit
/// the single seeded walk-in customer (see [Customer.isWalkIn]) — its name
/// and creditLimit are fixed by design so no one can accidentally extend
/// credit to walk-in sales.
class WalkInCustomerNotEditableException implements Exception {
  const WalkInCustomerNotEditableException();

  @override
  String toString() => 'The walk-in customer cannot be edited.';
}
