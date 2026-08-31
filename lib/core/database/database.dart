import 'package:drift/drift.dart';

import 'connection/connection.dart';
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

export 'connection/foreign_keys.dart' show enableForeignKeys;

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
  DukaDatabase() : super(openConnection());

  DukaDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(_singleManagerIndexSql);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(stockMovements, stockMovements.unitCost);
      }
      if (from < 3) {
        await m.addColumn(suppliers, suppliers.balance);
        await m.addColumn(purchases, purchases.paymentStatus);
      }
    },
  );
}
