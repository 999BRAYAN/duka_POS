import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [User] rows.
///
/// The database enforces that at most one user may hold role == 'manager'
/// (see idx_single_manager in AppDatabase); [createUser] is expected to
/// surface that violation as a domain-level exception rather than a raw
/// SqliteException once implemented.
abstract interface class UserRepository {
  Future<User> createUser({
    required String username,
    required String passwordHash,
    required String fullName,
    required String role,
  });

  Future<void> updateUser(User user);

  Future<void> deactivateUser(String uuid);

  Future<User?> getUserByUsername(String username);

  Future<User?> getUserByUuid(String uuid);

  /// Returns the matching user if [username]/[passwordHash] correspond to an
  /// active account, otherwise null.
  Future<User?> authenticate(String username, String passwordHash);

  Stream<List<User>> watchUsers();

  Future<bool> hasManager();
}
