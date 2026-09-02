import 'package:drift/drift.dart';

import 'customers_table.dart';
import 'users_table.dart';

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get invoiceNumber => text().unique()();
  IntColumn get customerId =>
      integer().nullable().references(Customers, #id)();
  IntColumn get userId => integer().references(Users, #id)();
  RealColumn get subtotal => real().withDefault(const Constant(0))();
  RealColumn get discount => real().withDefault(const Constant(0))();
  RealColumn get tax => real().withDefault(const Constant(0))();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().withDefault(const Constant(0))();
  // cash, mpesa, card, credit
  TextColumn get paymentMethod => text()();
  // Cost of goods sold and gross profit, computed once from each line's
  // unitCost-at-sale-time (SaleRepository.completeSale) and persisted here
  // rather than recomputed later — later cost/price changes shouldn't
  // rewrite the profit on a sale that already happened.
  RealColumn get cogs => real().withDefault(const Constant(0))();
  RealColumn get grossProfit => real().withDefault(const Constant(0))();
  // completed, void, refunded
  TextColumn get status => text().withDefault(const Constant('completed'))();
  // Why this sale was voided, and who did it. Required by SaleService.voidSale
  // — a void moves both stock and money, so the reason is the only record of
  // what actually happened at the counter.
  TextColumn get voidReason => text().nullable()();
  IntColumn get voidedByUserId => integer().nullable().references(Users, #id)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
