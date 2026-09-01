import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/data/repositories/profit_and_loss_report_repository_impl.dart';
import 'package:duka_pos/features/reports/data/repositories/sales_report_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _SaleFixture = ({DateTime date, double subtotal, double discount, double cogs, String status});
typedef _ExpenseFixture = ({DateTime date, double amount});

void main() {
  late DukaDatabase db;
  late SalesReportRepositoryImpl salesRepo;
  late ProfitAndLossReportRepositoryImpl pnlRepo;
  late int userId;

  // The target week: Monday 9 March 2026 through Sunday 15 March 2026 —
  // confirmed by DateRange's own tests. Fixtures below are deliberately
  // spread before, inside, and after this week (plus a void sale inside
  // it) so the test proves the boundary and status filters actually work,
  // not just that the totals look plausible.
  final range = DateRange.forPeriod(Period.week, DateTime(2026, 3, 12));

  // Every sale seeded into the DB. Indices annotate at a glance which
  // ones belong in the target week — that annotation is the "by hand"
  // judgment the test's manual sum below is built from, kept completely
  // separate from DateRange/the report repositories.
  final saleFixtures = <_SaleFixture>[
    // 0: Sunday 8 March — the day *before* the week starts.
    (date: DateTime(2026, 3, 8), subtotal: 1000, discount: 0, cogs: 400, status: 'completed'),
    // 1: Monday 9 March, 00:00 — the week's first instant.
    (date: DateTime(2026, 3, 9), subtotal: 500, discount: 20, cogs: 150, status: 'completed'),
    // 2: Wednesday 11 March.
    (date: DateTime(2026, 3, 11), subtotal: 300, discount: 0, cogs: 100, status: 'completed'),
    // 3: Friday 13 March.
    (date: DateTime(2026, 3, 13), subtotal: 700, discount: 50, cogs: 250, status: 'completed'),
    // 4: Friday 13 March, but void — inside the week, excluded by status.
    (date: DateTime(2026, 3, 13), subtotal: 9999, discount: 0, cogs: 9999, status: 'void'),
    // 5: Sunday 15 March, 23:59 — the week's last instant.
    (date: DateTime(2026, 3, 15, 23, 59), subtotal: 200, discount: 0, cogs: 80, status: 'completed'),
    // 6: Monday 16 March — the day *after* the week ends.
    (date: DateTime(2026, 3, 16), subtotal: 1000, discount: 0, cogs: 400, status: 'completed'),
  ];

  final expenseFixtures = <_ExpenseFixture>[
    (date: DateTime(2026, 3, 8), amount: 999), // before the week
    (date: DateTime(2026, 3, 10), amount: 150), // Tuesday, in week
    (date: DateTime(2026, 3, 14), amount: 200), // Saturday, in week
    (date: DateTime(2026, 3, 16), amount: 999), // after the week
  ];

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    salesRepo = SalesReportRepositoryImpl(db);
    pnlRepo = ProfitAndLossReportRepositoryImpl(db);

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

    for (var i = 0; i < saleFixtures.length; i++) {
      final fixture = saleFixtures[i];
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          uuid: 'sale-$i',
          invoiceNumber: 'INV-$i',
          userId: userId,
          subtotal: Value(fixture.subtotal),
          discount: Value(fixture.discount),
          total: Value(fixture.subtotal - fixture.discount),
          cogs: Value(fixture.cogs),
          paymentMethod: 'cash',
          status: Value(fixture.status),
          createdAt: fixture.date,
        ),
      );
    }

    for (var i = 0; i < expenseFixtures.length; i++) {
      final fixture = expenseFixtures[i];
      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          uuid: 'expense-$i',
          category: 'Rent',
          description: 'test expense',
          amount: fixture.amount,
          createdAt: fixture.date,
        ),
      );
    }
  });

  tearDown(() => db.close());

  test(
    'the sales report and the P&L report both agree, to the cent, with a manual sum of '
    'the same raw rows for one specific week',
    () async {
      // The "by hand" reconciliation: only fixtures 1, 2, 3, 5 are
      // completed sales inside the target week (0 and 6 are outside it;
      // 4 is inside but void). This list is written by hand from the
      // annotations above, not derived from DateRange or either report.
      final inWeekSales = [saleFixtures[1], saleFixtures[2], saleFixtures[3], saleFixtures[5]];
      final inWeekExpenses = [expenseFixtures[1], expenseFixtures[2]];

      final handSubtotal = inWeekSales.fold<double>(0, (sum, s) => sum + s.subtotal);
      final handDiscount = inWeekSales.fold<double>(0, (sum, s) => sum + s.discount);
      final handCogs = inWeekSales.fold<double>(0, (sum, s) => sum + s.cogs);
      final handRevenue = inWeekSales.fold<double>(0, (sum, s) => sum + (s.subtotal - s.discount));
      final handSaleCount = inWeekSales.length;
      final handExpenses = inWeekExpenses.fold<double>(0, (sum, e) => sum + e.amount);

      // Sanity check on the fixture data itself, independent of any
      // report: 500+300+700+200 subtotal, 20+0+50+0 discount,
      // 150+100+250+80 cogs, 150+200 expenses.
      expect(handSubtotal, 1700);
      expect(handDiscount, 70);
      expect(handCogs, 580);
      expect(handRevenue, 1630);
      expect(handSaleCount, 4);
      expect(handExpenses, 350);

      final salesReport = await salesRepo.getSalesReport(range);
      final pnlReport = await pnlRepo.getProfitAndLossReport(range);

      // Sales report vs. the manual sum.
      expect(salesReport.totalRevenue, handRevenue);
      expect(salesReport.saleCount, handSaleCount);
      expect(salesReport.averageSaleValue, handRevenue / handSaleCount);

      // P&L report's raw sums vs. the manual sum.
      expect(pnlReport.subtotal, handSubtotal);
      expect(pnlReport.discount, handDiscount);
      expect(pnlReport.cogs, handCogs);
      expect(pnlReport.expenses, handExpenses);

      // P&L's derived figures vs. the same manual sum, computed the same
      // way ProfitAndLossReport's getters are documented to compute them.
      final handNetRevenue = handSubtotal - handDiscount;
      final handGrossProfit = handNetRevenue - handCogs;
      final handNetProfit = handGrossProfit - handExpenses;
      expect(pnlReport.netRevenue, handNetRevenue);
      expect(pnlReport.grossProfit, handGrossProfit);
      expect(pnlReport.netProfit, handNetProfit);

      // Cross-report agreement: the sales report's total revenue and the
      // P&L report's net revenue describe the same completed sales in the
      // same week via two independent queries — they must land on the
      // same cent.
      expect(salesReport.totalRevenue, pnlReport.netRevenue);
    },
  );
}
