import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/users/domain/exceptions.dart';
import 'package:duka_pos/features/users/domain/repositories/user_repository.dart';
import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<User> createUser({
    required String username,
    required String passwordHash,
    required String fullName,
    required String role,
  }) async {
    try {
      return await _db.into(_db.users).insertReturning(
        UsersCompanion.insert(
          uuid: _uuid.v4(),
          username: username,
          passwordHash: passwordHash,
          fullName: fullName,
          role: role,
          createdAt: DateTime.now(),
        ),
      );
    } on SqliteException catch (e) {
      if (role == 'manager' &&
          e.message.contains('UNIQUE constraint failed: users.role')) {
        throw const ManagerAlreadyExistsException();
      }
      rethrow;
    }
  }

  @override
  Future<void> updateUser(User user) {
    return _db
        .update(_db.users)
        .replace(user.copyWith(updatedAt: Value(DateTime.now())));
  }

  @override
  Future<void> deactivateUser(String uuid) {
    return (_db.update(_db.users)..where((t) => t.uuid.equals(uuid))).write(
      UsersCompanion(isActive: const Value(false), updatedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<User?> getUserByUsername(String username) {
    return (_db.select(
      _db.users,
    )..where((t) => t.username.equals(username))).getSingleOrNull();
  }

  @override
  Future<User?> getUserByUuid(String uuid) {
    return (_db.select(
      _db.users,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Future<User?> authenticate(String username, String passwordHash) {
    return (_db.select(_db.users)..where(
          (t) =>
              t.username.equals(username) &
              t.passwordHash.equals(passwordHash) &
              t.isActive.equals(true),
        ))
        .getSingleOrNull();
  }

  @override
  Stream<List<User>> watchUsers() {
    return (_db.select(_db.users)..orderBy([
      (t) => OrderingTerm(expression: t.fullName),
    ])).watch();
  }

  @override
  Future<bool> hasManager() async {
    final manager =
        await (_db.select(_db.users)
              ..where((t) => t.role.equals('manager') & t.isActive.equals(true)))
            .getSingleOrNull();
    return manager != null;
  }
}
