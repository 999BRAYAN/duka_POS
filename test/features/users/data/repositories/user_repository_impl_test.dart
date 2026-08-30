import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/users/data/repositories/user_repository_impl.dart';
import 'package:duka_pos/features/users/domain/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late UserRepositoryImpl repo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = UserRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('createUser then authenticate succeeds with matching credentials', () async {
    await repo.createUser(
      username: 'jdoe',
      passwordHash: 'hash',
      fullName: 'Jane Doe',
      role: 'cashier',
    );

    final authenticated = await repo.authenticate('jdoe', 'hash');
    expect(authenticated?.username, 'jdoe');
  });

  test('authenticate fails with wrong password', () async {
    await repo.createUser(
      username: 'jdoe',
      passwordHash: 'hash',
      fullName: 'Jane Doe',
      role: 'cashier',
    );

    expect(await repo.authenticate('jdoe', 'wrong'), isNull);
  });

  test('authenticate fails for a deactivated user', () async {
    final user = await repo.createUser(
      username: 'jdoe',
      passwordHash: 'hash',
      fullName: 'Jane Doe',
      role: 'cashier',
    );
    await repo.deactivateUser(user.uuid);

    expect(await repo.authenticate('jdoe', 'hash'), isNull);
  });

  test('a second manager throws ManagerAlreadyExistsException', () async {
    await repo.createUser(
      username: 'boss1',
      passwordHash: 'hash',
      fullName: 'Boss One',
      role: 'manager',
    );

    expect(
      () => repo.createUser(
        username: 'boss2',
        passwordHash: 'hash',
        fullName: 'Boss Two',
        role: 'manager',
      ),
      throwsA(isA<ManagerAlreadyExistsException>()),
    );
  });

  test('hasManager reflects whether an active manager exists', () async {
    expect(await repo.hasManager(), isFalse);

    await repo.createUser(
      username: 'boss',
      passwordHash: 'hash',
      fullName: 'Boss',
      role: 'manager',
    );

    expect(await repo.hasManager(), isTrue);
  });
}
