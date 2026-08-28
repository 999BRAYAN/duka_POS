import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables/categories_table.dart';
import 'tables/credit_transactions_table.dart';
import 'tables/customers_table.dart';
import 'tables/expenses_table.dart';
import 'tables/products_table.dart';
import 'tables/purchase_items_table.dart';
import 'tables/purchases_table.dart';
import 'tables/sale_items_table.dart';
import 'tables/sales_table.dart';
import 'tables/stock_movements_table.dart';
import 'tables/suppliers_table.dart';
import 'tables/users_table.dart';

part 'database.g.dart';

// Only one user may ever hold the 'manager' role at a time. Enforced with a
// partial unique index rather than app-level checks so it holds regardless
// of which code path inserts/updates a user.
const _singleManagerIndexSql =
    "CREATE UNIQUE INDEX idx_single_manager ON users (role) WHERE role = 'manager';";

@DriftDatabase(
  tables: [
    Users,
    Categories,
    Products,
    Customers,
    Suppliers,
    StockMovements,
    Sales,
    SaleItems,
    Purchases,
    PurchaseItems,
    CreditTransactions,
    Expenses,
  ],
)
class DukaDatabase extends _$DukaDatabase {
  DukaDatabase() : super(_openConnection());

  DukaDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(_singleManagerIndexSql);
    },
  );
}

// SQLite has foreign key enforcement off by default. It must be set via
// setup on the raw connection (outside any transaction) - setting it in
// MigrationStrategy.beforeOpen via customStatement is silently ineffective.
void enableForeignKeys(Database database) {
  database.execute('PRAGMA foreign_keys = ON');
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'duka_pos.sqlite'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    return NativeDatabase.createInBackground(file, setup: enableForeignKeys);
  });
}
