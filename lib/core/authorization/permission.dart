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

  /// Creating staff logins, resetting their passwords, deactivating them.
  /// Held by the manager and admin only — a cashier who could create
  /// accounts could grant themselves any other permission.
  manageStaff,
}
