import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/sales/presentation/screens/sale_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late User cashier;
  late Customer janeDoe;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        sellingPrice: const Value(70),
        stock: const Value(10),
        createdAt: DateTime.now(),
      ),
    );
    cashier = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
    janeDoe = await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane',
        creditLimit: const Value(1000),
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
          currentUserProvider.overrideWith((ref) => cashier),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const SaleScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('happy path: tap a product into the cart and complete the sale', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();

    expect(find.text('70.00 each'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
    await tester.pumpAndSettle();

    expect(find.text('No items yet.'), findsOneWidget);

    final sales = await db.select(db.sales).get();
    expect(sales, hasLength(1));
    expect(sales.single.total, 70);
    expect(sales.single.paymentMethod, 'cash');

    final product = await db.select(db.products).getSingle();
    expect(product.stock, 9);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a credit sale with no customer selected shows an error and saves nothing', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Payment method'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
    await tester.pumpAndSettle();

    expect(find.text("A customer is required for payment method 'credit'."), findsOneWidget);
    expect(await db.select(db.sales).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets(
    'choosing a customer and leaving a balance adds it to that customer, within their credit limit',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Soda'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'Customer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jane').last);
      await tester.pumpAndSettle();

      // Newly picked customer defaults to "paid in full".
      expect(find.widgetWithText(TextField, 'Amount paid'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Amount paid'), '20');
      await tester.pump();

      expect(
        find.text("Remaining 50.00 will be added to this customer's balance."),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
      await tester.pumpAndSettle();

      expect(find.text('No items yet.'), findsOneWidget);

      final sale = await db.select(db.sales).getSingle();
      expect(sale.total, 70);
      expect(sale.amountPaid, 20);
      expect(sale.customerId, janeDoe.id);

      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(janeDoe.id))).getSingle();
      expect(customer.currentBalance, 50);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    "leaving a balance beyond the customer's credit limit shows a specific error and saves nothing",
    (tester) async {
      final amina = await db.into(db.customers).insertReturning(
        CustomersCompanion.insert(
          uuid: 'cust-2',
          name: 'Amina',
          creditLimit: const Value(30),
          createdAt: DateTime.now(),
        ),
      );

      await pumpScreen(tester);

      await tester.tap(find.text('Soda'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<int?>, 'Customer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Amina').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Amount paid'), '0');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "This sale would take Amina's balance to 70.00, over their credit limit of 30.00.",
        ),
        findsOneWidget,
      );
      expect(await db.select(db.sales).get(), isEmpty);

      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(amina.id))).getSingle();
      expect(customer.currentBalance, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets('holding a sale clears the cart, and resuming it restores the cart', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    expect(find.text('70.00 each'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hold sale'));
    await tester.pumpAndSettle();

    expect(find.text('No items yet.'), findsOneWidget);
    expect(find.text('Sale held.'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Held sales'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Walk-in customer')), findsOneWidget);
    expect(find.text('1 item(s) · 70.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.text('70.00 each'), findsOneWidget);
    expect(find.text('No items yet.'), findsNothing);

    await tester.tap(find.byTooltip('Held sales'));
    await tester.pumpAndSettle();
    expect(find.text('No held sales.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
