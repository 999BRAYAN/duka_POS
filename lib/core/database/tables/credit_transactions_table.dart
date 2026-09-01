import 'package:drift/drift.dart';

import 'customers_table.dart';
import 'sales_table.dart';

class CreditTransactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  IntColumn get customerId => integer().references(Customers, #id)();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  // CHARGE (a sale left a balance owing), PAYMENT (money collected),
  // REVERSAL (a charged sale was voided). CHARGE increases the balance;
  // PAYMENT and REVERSAL decrease it.
  TextColumn get type => text()();
  RealColumn get amount => real()();
  RealColumn get balanceAfter => real()();
  // How a PAYMENT was taken (cash, mpesa, card — same free-form convention
  // as Sales.paymentMethod). Null for CHARGE rows, which have no payment
  // method of their own — the originating Sale already carries one.
  TextColumn get method => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
