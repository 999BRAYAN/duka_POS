import 'package:drift/drift.dart' show Value;
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/security/password_hasher.dart';
import 'package:duka_pos/features/users/domain/repositories/user_repository.dart';

/// Thrown when a sign-in attempt doesn't match an active account.
///
/// Deliberately one exception for both "no such username" and "wrong
/// password": telling them apart would let anyone discover which usernames
/// exist by watching which error comes back.
class InvalidCredentialsException implements Exception {
  const InvalidCredentialsException();

  @override
  String toString() =>
      "That username and password don't match. Check the password and try again.";
}

/// Thrown when the first-run setup is attempted on a shop that already has
/// a manager — there can only ever be one.
class ManagerAlreadyExistsForSetupException implements Exception {
  const ManagerAlreadyExistsForSetupException();

  @override
  String toString() => 'This shop already has a manager account. Sign in instead.';
}

/// Thrown when a password is too short to be worth hashing.
class WeakPasswordException implements Exception {
  const WeakPasswordException(this.minimumLength);

  final int minimumLength;

  @override
  String toString() => 'Use at least $minimumLength characters.';
}

/// Signing in, and creating the accounts that can sign in.
///
/// Passwords only ever exist in plaintext inside these methods: everything
/// below this layer stores and compares [PasswordHasher] output.
class AuthService {
  AuthService(this._users);

  final UserRepository _users;

  /// Short enough not to fight a shopkeeper at a counter, long enough that
  /// a four-digit PIN doesn't slip through.
  static const minimumPasswordLength = 6;

  /// Whether anyone can sign in yet. False on a brand-new install, which is
  /// what sends the app to first-run setup instead of the login screen.
  Future<bool> isSetUp() => _users.hasManager();

  /// Verifies [username]/[password] and returns the signed-in user.
  Future<User> signIn({required String username, required String password}) async {
    final user = await _users.getUserByUsername(username);

    // Verify even when there's no such user, against a throwaway hash, so
    // a missing username doesn't return noticeably faster than a wrong
    // password and reveal which accounts exist.
    if (user == null) {
      PasswordHasher.verify(password, PasswordHasher.hash('no such user'));
      throw const InvalidCredentialsException();
    }
    if (!user.isActive) throw const InvalidCredentialsException();
    if (!PasswordHasher.verify(password, user.passwordHash)) {
      throw const InvalidCredentialsException();
    }

    return user;
  }

  /// Creates the shop's one manager account on a fresh install.
  Future<User> createFirstManager({
    required String username,
    required String password,
    required String fullName,
  }) async {
    if (await _users.hasManager()) {
      throw const ManagerAlreadyExistsForSetupException();
    }
    return _createUser(
      username: username,
      password: password,
      fullName: fullName,
      role: 'manager',
    );
  }

  /// Creates any other account. Authorization for this lives in the screen
  /// that calls it — only a manager can reach the user-management screen.
  Future<User> createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) {
    return _createUser(
      username: username,
      password: password,
      fullName: fullName,
      role: role,
    );
  }

  /// Replaces [user]'s password. Used both by a manager resetting a
  /// cashier's password and by anyone changing their own.
  Future<void> changePassword({required User user, required String newPassword}) {
    _assertStrongEnough(newPassword);
    return _users.updateUser(
      user.copyWith(
        passwordHash: PasswordHasher.hash(newPassword),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<User> _createUser({
    required String username,
    required String password,
    required String fullName,
    required String role,
  }) async {
    _assertStrongEnough(password);
    return _users.createUser(
      username: username.trim(),
      passwordHash: PasswordHasher.hash(password),
      fullName: fullName.trim(),
      role: role,
    );
  }

  void _assertStrongEnough(String password) {
    if (password.length < minimumPasswordLength) {
      throw const WeakPasswordException(minimumPasswordLength);
    }
  }
}
