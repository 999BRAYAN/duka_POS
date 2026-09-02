/// A single grantable capability, checked via [AuthorizationService] before
/// a mutating action is allowed to proceed.
enum Permission {
  manageProducts,
  adjustStock,
  receiveStock,
  processSale,
  manageCustomers,
  overrideCreditLimit,
  manageExpenses,

  /// Reversing a completed sale: the goods go back into stock and any
  /// unpaid balance comes off the customer. Held by a manager only — a
  /// cashier who could void their own sales could take cash out of the till
  /// and erase the record of it.
  voidSale,

  /// Creating staff logins, resetting their passwords, deactivating them.
  /// Held by the manager and admin only — a cashier who could create
  /// accounts could grant themselves any other permission.
  manageStaff,
}
