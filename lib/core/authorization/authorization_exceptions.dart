import 'permission.dart';

/// Thrown by [AuthorizationService.require] when the current user (or no
/// signed-in user at all) lacks the requested [permission].
class UnauthorizedException implements Exception {
  const UnauthorizedException(this.permission);

  final Permission permission;

  @override
  String toString() =>
      'Current user does not have permission: ${permission.name}';
}
