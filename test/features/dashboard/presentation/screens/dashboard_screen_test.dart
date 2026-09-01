import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    final userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    )).id;

    // A low-stock product (stock <= reorderLevel) for the "low stock" KPI.
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(5),
        reorderLevel: const Value(10),
        createdAt: DateTime.now(),
      ),
    );

    // A customer with an outstanding balance for the "credit outstanding" KPI.
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane',
        creditLimit: const Value(1000),
        currentBalance: const Value(150),
        createdAt: DateTime.now(),
      ),
    );

    final now = DateTime.now();

    // Today's sale: drives both KPI cards and the trend chart's last point.
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

    // A sale 3 days ago, to give the trend chart a second non-zero point.
    await db.into(db.sales).insert(
      SalesCompanion.insert(
        uuid: 'sale-3-days-ago',
        invoiceNumber: 'INV-2',
        userId: userId,
        subtotal: const Value(150),
        total: const Value(150),
        paymentMethod: 'cash',
        createdAt: DateTime(now.year, now.month, now.day - 3, 12),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    "KPI cards show today's revenue/net profit plus low-stock and credit-outstanding "
    'numbers from the existing repositories',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text("Today's revenue"), findsOneWidget);
      expect(find.text('200.00'), findsWidgets); // revenue and net profit both read 200.00
      expect(find.text('Low stock'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Credit outstanding'), findsOneWidget);
      expect(find.text('150.00'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'the 7-day trend chart has one point per day, with data landing on the right day',
    (tester) async {
      await pumpScreen(tester);

      final chart = tester.widget<LineChart>(find.byType(LineChart));
      final spots = chart.data.lineBarsData.single.spots;

      expect(spots, hasLength(7));
      expect(spots[6].y, 200); // today, the last point
      expect(spots[3].y, 150); // 3 days ago
      expect(spots[0].y, 0);
      expect(spots[1].y, 0);
      expect(spots[2].y, 0);
      expect(spots[4].y, 0);
      expect(spots[5].y, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
