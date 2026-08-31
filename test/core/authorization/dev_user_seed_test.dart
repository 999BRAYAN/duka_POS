import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/dev_user_seed.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates and signs in a manager when no user exists', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await seedDevUser(container);

    final user = container.read(currentUserProvider);
    expect(user, isNotNull);
    expect(user!.role, 'manager');

    final rows = await db.select(db.users).get();
    expect(rows, hasLength(1));
  });

  test('signs in the existing active user instead of creating another one', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });

    final existing = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'existing',
        username: 'admin',
        passwordHash: 'hash',
        fullName: 'Existing Admin',
        role: 'admin',
        createdAt: DateTime.now(),
      ),
    );

    await seedDevUser(container);

    final user = container.read(currentUserProvider);
    expect(user?.uuid, existing.uuid);

    final rows = await db.select(db.users).get();
    expect(rows, hasLength(1));
  });

  test('skips a deactivated user and creates a fresh manager', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await db.into(db.users).insert(
      UsersCompanion.insert(
        uuid: 'inactive',
        username: 'gone',
        passwordHash: 'hash',
        fullName: 'Former Employee',
        role: 'cashier',
        isActive: const Value(false),
        createdAt: DateTime.now(),
      ),
    );

    await seedDevUser(container);

    final user = container.read(currentUserProvider);
    expect(user?.role, 'manager');
    expect(user?.isActive, isTrue);
  });
}
