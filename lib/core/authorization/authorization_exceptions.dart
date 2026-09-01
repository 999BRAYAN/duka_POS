import 'permission.dart';

/// Thrown by [AuthorizationService.require] when the current user (or no
/// signed-in user at all) lacks the requested [permission].
class UnauthorizedException implements Exception {
  const UnauthorizedException(this.permission);

  final Permission permission;

  /// Written for the person who hits it at a counter, not for a log: every
  /// screen surfaces this string directly. It names the action in the
  /// shop's own terms and says who to ask, rather than naming the
  /// permission constant.
  @override
  String toString() => switch (permission) {
    Permission.manageProducts =>
      'Only a manager can change the product list. Ask them to add or edit this.',
    Permission.adjustStock =>
      'Only a manager can correct stock counts. Ask them to make this change.',
    Permission.receiveStock =>
      'Only a manager can receive stock from a supplier.',
    Permission.processSale => 'You are not allowed to complete sales.',
    Permission.manageCustomers =>
      'Only a manager can change customer accounts or record payments.',
    Permission.overrideCreditLimit =>
      "Only a manager can approve a sale beyond a customer's credit limit.",
    Permission.manageExpenses => 'Only a manager can record shop expenses.',
    Permission.manageStaff => 'Only a manager can manage staff logins.',
  };
}
