import 'package:drift/drift.dart';

class Customers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  RealColumn get creditLimit => real().withDefault(const Constant(0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0))();
  // The single seeded walk-in customer (see seedWalkInCustomer) — always
  // creditLimit 0, and CustomerService.updateCustomer refuses to edit this
  // row regardless of who's asking. At most one row should ever have this
  // set; nothing in the schema enforces that, since seeding is idempotent.
  BoolColumn get isWalkIn => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
