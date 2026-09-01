import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/data/repositories/profit_and_loss_report_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late ProfitAndLossReportRepositoryImpl repo;
  late int userId;
  var idCounter = 0;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = ProfitAndLossReportRepositoryImpl(db);

    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  Future<void> insertSale({
    required double subtotal,
    double discount = 0,
    double cogs = 0,
    required DateTime createdAt,
    String status = 'completed',
  }) {
    final id = idCounter++;
    return db.into(db.sales).insert(
      SalesCompanion.insert(
        uuid: 'sale-$id',
        invoiceNumber: 'INV-$id',
        userId: userId,
        subtotal: Value(subtotal),
        discount: Value(discount),
        total: Value(subtotal - discount),
        cogs: Value(cogs),
        paymentMethod: 'cash',
        status: Value(status),
        createdAt: createdAt,
      ),
    );
  }

  Future<void> insertExpense({required double amount, required DateTime createdAt}) {
    final id = idCounter++;
    return db.into(db.expenses).insert(
      ExpensesCompanion.insert(
        uuid: 'expense-$id',
        category: 'Rent',
        description: 'test expense',
        amount: amount,
        createdAt: createdAt,
      ),
    );
  }

  test(
    'sums subtotal/discount/cogs from completed sales and amount from expenses in range, '
    'then derives net revenue, gross profit and net profit from those sums',
    () async {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

      await insertSale(subtotal: 1000, discount: 50, cogs: 400, createdAt: DateTime(2026, 3, 5));
      await insertSale(subtotal: 500, createdAt: DateTime(2026, 3, 20), cogs: 200);

      // Outside the range — must not affect any sum.
      await insertSale(subtotal: 9999, createdAt: DateTime(2026, 2, 28));

      // Inside the range but void — excluded the same way the sales report
      // excludes it.
      await insertSale(
        subtotal: 9999,
        discount: 9999,
        cogs: 9999,
        createdAt: DateTime(2026, 3, 10),
        status: 'void',
      );

      await insertExpense(amount: 300, createdAt: DateTime(2026, 3, 8));
      await insertExpense(amount: 200, createdAt: DateTime(2026, 3, 25));
      // Outside the range — must not affect the total.
      await insertExpense(amount: 9999, createdAt: DateTime(2026, 4, 1));

      final report = await repo.getProfitAndLossReport(range);

      expect(report.subtotal, 1500); // 1000 + 500
      expect(report.discount, 50);
      expect(report.cogs, 600); // 400 + 200
      expect(report.expenses, 500); // 300 + 200

      // Derived, not stored — verify the math directly rather than trusting
      // the getters implement it correctly by construction.
      expect(report.netRevenue, 1450); // 1500 - 50
      expect(report.grossProfit, 850); // 1450 - 600
      expect(report.netProfit, 350); // 850 - 500
    },
  );

  test('a range with no activity reports all zeros', () async {
    final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

    final report = await repo.getProfitAndLossReport(range);

    expect(report.subtotal, 0);
    expect(report.discount, 0);
    expect(report.cogs, 0);
    expect(report.expenses, 0);
    expect(report.netRevenue, 0);
    expect(report.grossProfit, 0);
    expect(report.netProfit, 0);
  });
}
