import 'package:drift/drift.dart';

import 'users_table.dart';

class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get category => text()();
  TextColumn get description => text()();
  RealColumn get amount => real()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
