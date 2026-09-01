import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Ensures exactly one [Customer] row has [Customer.isWalkIn] set, creating
/// it on first run. Idempotent, same pattern as seedDevUser: safe to call on
/// every app start. Inserted directly against the database rather than
/// through [CustomerService] — that service deliberately never exposes
/// isWalkIn, so this is the only code path that ever sets it.
Future<void> seedWalkInCustomer(ProviderContainer container) async {
  final db = container.read(databaseProvider);

  final existing = await (db.select(
    db.customers,
  )..where((t) => t.isWalkIn.equals(true))..limit(1)).getSingleOrNull();
  if (existing != null) return;

  await db.into(db.customers).insert(
    CustomersCompanion.insert(
      uuid: _uuid.v4(),
      name: 'Walk-in Customer',
      creditLimit: const Value(0),
      isWalkIn: const Value(true),
      createdAt: DateTime.now(),
    ),
  );
}
