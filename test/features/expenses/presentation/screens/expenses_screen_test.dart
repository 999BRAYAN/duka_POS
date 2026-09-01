import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:duka_pos/features/reports/data/repositories/profit_and_loss_report_repository_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late User manager;
  late User cashier;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    manager = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-manager',
        username: 'amina',
        passwordHash: 'hash',
        fullName: 'Amina Wanjiru',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    );
    cashier = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-cashier',
        username: 'peter',
        passwordHash: 'hash',
        fullName: 'Peter Otieno',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester, {required User as}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => as),
        ],
        child: const MaterialApp(home: ExpensesScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> recordExpense(
    WidgetTester tester, {
    required String amount,
    required String description,
  }) async {
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), amount);
    await tester.enterText(
      find.widgetWithText(TextField, 'What was it for?'),
      description,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Record expense'));
    await tester.pumpAndSettle();
  }

  testWidgets('recording an expense saves it and lists it', (tester) async {
    await pumpScreen(tester, as: manager);

    await recordExpense(tester, amount: '1500', description: 'Delivery from Nyeri');

    final expense = await db.select(db.expenses).getSingle();
    expect(expense.amount, 1500);
    expect(expense.description, 'Delivery from Nyeri');
    expect(expense.category, 'Rent', reason: 'the first category is the default');
    expect(expense.userId, manager.id, reason: 'the expense records who entered it');

    expect(find.text('Delivery from Nyeri'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('a cashier cannot record an expense', (tester) async {
    await pumpScreen(tester, as: cashier);

    // The form is not offered at all, and the service would refuse anyway.
    expect(find.widgetWithText(FilledButton, 'Record expense'), findsNothing);
    expect(await db.select(db.expenses).get(), isEmpty);

    await disposeScreen(tester);
  });

  testWidgets(
    'a recorded expense reaches the profit and loss report and cuts net profit',
    (tester) async {
      // A sale to give the report some revenue to work against.
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          uuid: 'sale-1',
          invoiceNumber: 'INV-000001',
          userId: manager.id,
          subtotal: const Value(1000),
          total: const Value(1000),
          amountPaid: const Value(1000),
          cogs: const Value(600),
          paymentMethod: 'cash',
          createdAt: DateTime.now(),
        ),
      );

      final range = DateRange.forPeriod(Period.today);
      final reports = ProfitAndLossReportRepositoryImpl(db);

      final before = await reports.getProfitAndLossReport(range);
      expect(before.expenses, 0);
      expect(before.netProfit, 400, reason: '1000 revenue less 600 cost');

      await pumpScreen(tester, as: manager);
      await recordExpense(tester, amount: '250', description: 'Electricity token');
      await disposeScreen(tester);

      final after = await reports.getProfitAndLossReport(range);
      expect(after.expenses, 250);
      expect(
        after.netProfit,
        150,
        reason: 'net profit drops by the expense — the whole point of this screen',
      );
      expect(
        after.grossProfit,
        before.grossProfit,
        reason: 'an expense is not a cost of goods; gross profit is unchanged',
      );
    },
  );
}
