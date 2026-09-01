import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/reports/presentation/screens/reports_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('period selector', () {
    setUp(() async {
      final now = DateTime.now();

      // Today's sale — visible under both "Today" and "This year".
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          uuid: 'sale-today',
          invoiceNumber: 'INV-1',
          userId: userId,
          subtotal: const Value(200),
          total: const Value(200),
          paymentMethod: 'cash',
          createdAt: now,
        ),
      );

      // A sale on January 1st of this year — outside "Today" (unless the
      // test happens to run on Jan 1st), but always inside "This year".
      await db.into(db.sales).insert(
        SalesCompanion.insert(
          uuid: 'sale-jan-1',
          invoiceNumber: 'INV-2',
          userId: userId,
          subtotal: const Value(300),
          total: const Value(300),
          paymentMethod: 'cash',
          createdAt: DateTime(now.year, 1, 1, 12),
        ),
      );
    });

    testWidgets('defaults to Today, scoping the sales report to just today\'s sale', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('200.00'), findsWidgets); // total revenue + average sale
      expect(find.text('300.00'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });

    testWidgets(
      'choosing "This year" re-scopes the same sales report to include the whole year',
      (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.widgetWithText(ChoiceChip, 'This year'));
        await tester.pumpAndSettle();

        expect(find.text('500.00'), findsOneWidget); // 200 + 300
        expect(find.text('2'), findsOneWidget); // sale count

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
      },
    );
  });

  testWidgets('the profit & loss tab derives net revenue, gross profit and net profit', (
    tester,
  ) async {
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        uuid: 'sale-1',
        invoiceNumber: 'INV-1',
        userId: userId,
        subtotal: const Value(200),
        total: const Value(200),
        cogs: const Value(50),
        paymentMethod: 'cash',
        createdAt: DateTime.now(),
      ),
    );

    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(Tab, 'Profit & loss'));
    await tester.pumpAndSettle();

    expect(find.text('Net revenue'), findsOneWidget);
    expect(find.text('Gross profit'), findsOneWidget);
    expect(find.text('Net profit'), findsOneWidget);
    // Subtotal 200, no discount -> net revenue 200; cogs 50 -> gross
    // profit 150; no expenses -> net profit 150. Each appears once next
    // to its label, but 150 shows twice (gross profit and net profit).
    expect(find.text('150.00'), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'the inventory tab shows a highlighted low-stock row and a movement chart with the '
    "period's received/sold totals",
    (tester) async {
      final productId = (await db.into(db.products).insertReturning(
        ProductsCompanion.insert(
          uuid: 'prod-1',
          name: 'Soda',
          stock: const Value(3),
          reorderLevel: const Value(10),
          createdAt: DateTime.now(),
        ),
      )).id;

      final movements = StockMovementRepositoryImpl(db);
      await movements.recordMovement(productId: productId, type: 'PURCHASE', quantity: 15);
      await movements.recordMovement(productId: productId, type: 'SALE', quantity: -5);

      await pumpScreen(tester);

      await tester.tap(find.widgetWithText(Tab, 'Inventory'));
      await tester.pumpAndSettle();

      expect(find.text('Soda'), findsOneWidget);

      final chart = tester.widget<BarChart>(find.byType(BarChart));
      final byX = {for (final g in chart.data.barGroups) g.x: g.barRods.single.toY};
      expect(byX[0], 15); // PURCHASE, first in the fixed type order
      expect(byX[1], -5); // SALE
      expect(byX[2], 0); // RETURN
      expect(byX[3], 0); // ADJUSTMENT

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
