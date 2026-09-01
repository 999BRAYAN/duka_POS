import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/credit/presentation/screens/receive_payment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

User _userWithRole(String role) {
  return User(
    id: 1,
    uuid: 'u1',
    username: 'jdoe',
    passwordHash: 'hash',
    fullName: 'Jane Doe',
    role: role,
    isActive: true,
    createdAt: DateTime(2026),
  );
}

void main() {
  late DukaDatabase db;
  late Customer customer;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    customer = await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane',
        creditLimit: const Value(1000),
        currentBalance: const Value(500),
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  final navigatorKey = GlobalKey<NavigatorState>();

  // ReceivePaymentScreen calls Navigator.pop() on success, so it needs a
  // real route underneath it (pushed, not the app's only route) or that
  // pop would have nowhere to go.
  Future<void> pumpScreen(WidgetTester tester, User user) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => user),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => ReceivePaymentScreen(customer: customer)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('records a payment and decreases the balance', (tester) async {
    await pumpScreen(tester, _userWithRole('manager'));

    expect(find.text('Current balance: 500.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '200');
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Payment method'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M-Pesa').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();

    expect(find.byType(ReceivePaymentScreen), findsNothing);

    final reloaded = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(customer.id))).getSingle();
    expect(reloaded.currentBalance, 300);

    final transaction = await db.select(db.creditTransactions).getSingle();
    expect(transaction.type, 'PAYMENT');
    expect(transaction.method, 'mpesa');
    expect(transaction.amount, 200);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an amount of zero shows an error and saves nothing', (tester) async {
    await pumpScreen(tester, _userWithRole('manager'));

    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();

    expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
    expect(await db.select(db.creditTransactions).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a cashier sees a permission error and saves nothing', (tester) async {
    await pumpScreen(tester, _userWithRole('cashier'));

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '200');
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();

    expect(find.text("You don't have permission to record a payment."), findsOneWidget);
    expect(await db.select(db.creditTransactions).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
