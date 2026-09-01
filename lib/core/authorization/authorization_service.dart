import 'package:duka_pos/core/database/database.dart';

import 'authorization_exceptions.dart';
import 'permission.dart';

/// Maps a signed-in [User]'s role to the [Permission]s it grants. Roles come
/// from the `users.role` column (admin, manager, cashier — see UsersTable).
const _rolePermissions = <String, Set<Permission>>{
  'admin': {
    Permission.manageProducts,
    Permission.adjustStock,
    Permission.receiveStock,
    Permission.processSale,
    Permission.manageCustomers,
  },
  'manager': {
    Permission.manageProducts,
    Permission.adjustStock,
    Permission.receiveStock,
    Permission.processSale,
    Permission.manageCustomers,
  },
  // Cashiers can't touch the catalog, inventory, or purchasing, but
  // ringing up a sale is their job — this is the one permission they hold.
  'cashier': {Permission.processSale},
};

/// Checks whether the current user is allowed to perform a given action.
/// Takes the current user directly rather than reading session state itself,
/// so it stays easy to construct in tests and doesn't need to know how the
/// session is stored.
class AuthorizationService {
  const AuthorizationService(this._currentUser);

  final User? _currentUser;

  bool can(Permission permission) {
    final role = _currentUser?.role;
    if (role == null) return false;
    return _rolePermissions[role]?.contains(permission) ?? false;
  }

  /// Throws [UnauthorizedException] if [can] would return false.
  void require(Permission permission) {
    if (!can(permission)) {
      throw UnauthorizedException(permission);
    }
  }
}
