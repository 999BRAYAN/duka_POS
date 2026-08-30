/// Thrown by [UserRepository.createUser] when a second user with
/// `role == 'manager'` is created while one is already active — surfaced in
/// place of the raw `SqliteException` from the `idx_single_manager`
/// constraint (see DukaDatabase).
class ManagerAlreadyExistsException implements Exception {
  const ManagerAlreadyExistsException();

  @override
  String toString() =>
      'A manager already exists; only one user may hold the manager role at a time.';
}
