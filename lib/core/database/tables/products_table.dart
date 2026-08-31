import 'package:drift/drift.dart';

import 'categories_table.dart';

class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  TextColumn get unit => text().withDefault(const Constant('pcs'))();
  RealColumn get costPrice => real().withDefault(const Constant(0))();
  RealColumn get sellingPrice => real().withDefault(const Constant(0))();
  RealColumn get minSellingPrice => real().withDefault(const Constant(0))();
  // Never written directly outside StockMovementRepository.recordMovement —
  // that's the only path allowed to change this column, so every change is
  // backed by an audit-trail row in StockMovements. See that repository's
  // class doc before adding another writer.
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get reorderLevel => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
