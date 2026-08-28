import 'package:drift/drift.dart';

import 'products_table.dart';
import 'users_table.dart';

class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  IntColumn get productId => integer().references(Products, #id)();
  // IN, OUT, ADJUSTMENT, SALE, PURCHASE, RETURN
  TextColumn get type => text()();
  RealColumn get quantity => real()();
  TextColumn get reference => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
