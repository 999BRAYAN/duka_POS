import 'package:drift/drift.dart';

import 'customers_table.dart';
import 'sales_table.dart';

class CreditTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  // CHARGE, PAYMENT
  TextColumn get type => text()();
  RealColumn get amount => real()();
  RealColumn get balanceAfter => real()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
