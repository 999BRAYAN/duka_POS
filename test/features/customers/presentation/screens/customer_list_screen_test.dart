import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_list_screen.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_statement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late User manager;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    manager = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'manager',
        passwordHash: 'hash',
        fullName: 'Manager One',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => manager),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const CustomerListScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists customers with balances, walk-in included and marked', (tester) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane',
        creditLimit: const Value(500),
        currentBalance: const Value(120),
        createdAt: DateTime.now(),
      ),
    );
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        uuid: 'walk-in',
        name: 'Walk-in Customer',
        isWalkIn: const Value(true),
        createdAt: DateTime.now(),
      ),
    );

    await pumpScreen(tester);

    expect(find.text('Jane'), findsOneWidget);
    expect(find.text('120.00'), findsOneWidget);
    expect(find.text('Walk-in Customer'), findsOneWidget);
    expect(find.text('Walk-in'), findsOneWidget); // the badge chip

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('search filters by name', (tester) async {
    await db.into(
      db.customers,
    ).insert(CustomersCompanion.insert(uuid: 'cust-1', name: 'Jane', createdAt: DateTime.now()));
    await db.into(
      db.customers,
    ).insert(CustomersCompanion.insert(uuid: 'cust-2', name: 'Amina', createdAt: DateTime.now()));

    await pumpScreen(tester);
    expect(find.text('Jane'), findsOneWidget);
    expect(find.text('Amina'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ami');
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsNothing);
    expect(find.text('Amina'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('add customer button navigates to the form', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add customer'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerFormScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('receive payment is disabled for the walk-in customer', (tester) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        uuid: 'walk-in',
        name: 'Walk-in Customer',
        isWalkIn: const Value(true),
        createdAt: DateTime.now(),
      ),
    );

    await pumpScreen(tester);

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('The walk-in customer never carries a balance to pay down.'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('statement button navigates to the statement screen', (tester) async {
    await db.into(
      db.customers,
    ).insert(CustomersCompanion.insert(uuid: 'cust-1', name: 'Jane', createdAt: DateTime.now()));

    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Statement'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomerStatementScreen), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
