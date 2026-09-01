import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_statement_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
        currentBalance: const Value(300),
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: CustomerStatementScreen(customer: customer)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows an empty state when there is no credit activity', (tester) async {
    await pumpScreen(tester);

    expect(find.text('No credit activity yet.'), findsOneWidget);
    expect(find.text('300.00'), findsWidgets); // current balance summary tile

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('lists a credit sale and a payment with a running balance', (tester) async {
    final user = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
    final sale = await db.into(db.sales).insertReturning(
      SalesCompanion.insert(
        uuid: 'sale-1',
        invoiceNumber: 'INV-000001',
        customerId: Value(customer.id),
        userId: user.id,
        subtotal: const Value(500),
        total: const Value(500),
        amountPaid: const Value(200),
        paymentMethod: 'credit',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    // The CHARGE row is what puts the sale on the statement — the sale row
    // alone no longer does, now that every balance change is a credit
    // transaction.
    await db.into(db.creditTransactions).insert(
      CreditTransactionsCompanion.insert(
        uuid: 'txn-charge',
        customerId: customer.id,
        saleId: Value(sale.id),
        type: 'CHARGE',
        amount: 300,
        balanceAfter: 300,
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    await db.into(db.creditTransactions).insert(
      CreditTransactionsCompanion.insert(
        uuid: 'txn-1',
        customerId: customer.id,
        type: 'PAYMENT',
        amount: 100,
        balanceAfter: 200,
        method: const Value('cash'),
        createdAt: DateTime(2026, 1, 2),
      ),
    );

    await pumpScreen(tester);

    expect(find.text('Credit sale'), findsOneWidget);
    expect(find.text('INV-000001'), findsOneWidget);
    expect(find.text('+300.00'), findsOneWidget); // 500 total - 200 paid

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('cash'), findsOneWidget);
    expect(find.text('-100.00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
