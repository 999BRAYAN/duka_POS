import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/data/walk_in_customer_seed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates the walk-in customer when none exists', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await seedWalkInCustomer(container);

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
    expect(rows.single.isWalkIn, isTrue);
    expect(rows.single.creditLimit, 0);
    expect(rows.single.name, 'Walk-in Customer');
  });

  test('is idempotent: calling it again does not create a second row', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await seedWalkInCustomer(container);
    await seedWalkInCustomer(container);

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
  });

  test('does not touch an already-existing walk-in row', () async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    final container = ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(() {
      container.dispose();
      db.close();
    });

    await seedWalkInCustomer(container);
    final firstUuid = (await db.select(db.customers).getSingle()).uuid;

    await seedWalkInCustomer(container);
    final second = await db.select(db.customers).getSingle();

    expect(second.uuid, firstUuid);
  });
}
