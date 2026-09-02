import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/sales/presentation/screens/sale_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selling now spans two screens — the order is built on one and paid for on
/// another — so these drive the whole path: tap products, review, then pay.
void main() {
  late DukaDatabase db;
  late User cashier;
  late User manager;
  late Customer janeDoe;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    final drinks = await db.into(db.categories).insertReturning(
      CategoriesCompanion.insert(uuid: 'cat-1', name: 'Drinks', createdAt: DateTime.now()),
    );
    final hardware = await db.into(db.categories).insertReturning(
      CategoriesCompanion.insert(uuid: 'cat-2', name: 'Hardware', createdAt: DateTime.now()),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        sku: const Value('SOD-1'),
        categoryId: Value(drinks.id),
        sellingPrice: const Value(70),
        stock: const Value(10),
        createdAt: DateTime.now(),
      ),
    );
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        uuid: 'prod-2',
        name: 'Gate valve',
        sku: const Value('GTV-1'),
        categoryId: Value(hardware.id),
        sellingPrice: const Value(850),
        stock: const Value(5),
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
    manager = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-2',
        username: 'amina',
        passwordHash: 'hash',
        fullName: 'Amina Wanjiru',
        role: 'manager',
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

  Future<void> pumpScreen(WidgetTester tester, {User? as}) async {
    // Selling is a desktop screen: a product grid beside an order panel, and
    // above 1100 the navigation sits on the page too. The default 800x600
    // test surface is narrower than any real till window, so testing at it
    // would be testing a layout nobody uses.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => as ?? cashier),
        ],
        child: const MaterialApp(home: SaleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  /// Adds [product] to the order, then moves to the payment screen.
  Future<void> reviewOrder(WidgetTester tester, {String product = 'Soda'}) async {
    await tester.tap(find.text(product));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Review order'));
    await tester.pumpAndSettle();
  }

  Future<void> completeSale(WidgetTester tester) async {
    await tester.tap(find.textContaining('Complete sale'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseCustomer(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('an order is built on one screen and paid for on the next', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();

    // Payment belongs to the second screen and must not be on this one.
    expect(find.textContaining('Complete sale'), findsNothing);
    expect(find.text('Order total'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Review order'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm & pay'), findsOneWidget);
    await completeSale(tester);

    final sales = await db.select(db.sales).get();
    expect(sales, hasLength(1));
    expect(sales.single.total, 70);
    expect(sales.single.paymentMethod, 'cash');
    expect((await db.select(db.products).get()).firstWhere((p) => p.name == 'Soda').stock, 9);

    // Back on the order screen with the order cleared.
    expect(find.text('Tap a product to start the order.'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('searching narrows the products to what was typed', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Soda'), findsOneWidget);
    expect(find.text('Gate valve'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Search by name, SKU or barcode'), 'valve');
    await tester.pumpAndSettle();

    expect(find.text('Soda'), findsNothing);
    expect(find.text('Gate valve'), findsOneWidget);

    // SKU finds it too — the code on the box is what a hardware shop reads.
    await tester.enterText(find.widgetWithText(TextField, 'Search by name, SKU or barcode'), 'SOD-1');
    await tester.pumpAndSettle();

    expect(find.text('Soda'), findsOneWidget);
    expect(find.text('Gate valve'), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('filtering by category shows only that category', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hardware (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Gate valve'), findsOneWidget);
    expect(find.text('Soda'), findsNothing);

    await disposeScreen(tester);
  });

  testWidgets('a credit sale with no customer is refused and saves nothing', (tester) async {
    await pumpScreen(tester);
    await reviewOrder(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit').last);
    await tester.pumpAndSettle();

    await completeSale(tester);

    expect(find.textContaining('customer is required'), findsOneWidget);
    expect(await db.select(db.sales).get(), isEmpty);

    await disposeScreen(tester);
  });

  testWidgets('a balance left on a named customer lands on their account', (tester) async {
    await pumpScreen(tester);
    await reviewOrder(tester);
    await chooseCustomer(tester, 'Jane');

    // Choosing a customer offers the amount-paid field, defaulted to the
    // whole total so leaving a balance is deliberate.
    final paidField = find.widgetWithText(TextField, 'Amount paid now');
    expect(paidField, findsOneWidget);
    expect(tester.widget<TextField>(paidField).controller!.text, '70.00');

    await tester.enterText(paidField, '20');
    await tester.pumpAndSettle();
    expect(find.textContaining('Remaining 50.00'), findsOneWidget);

    await completeSale(tester);

    final sale = await db.select(db.sales).getSingle();
    expect(sale.amountPaid, 20);
    final customer = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(janeDoe.id))).getSingle();
    expect(customer.currentBalance, 50);

    await disposeScreen(tester);
  });

  testWidgets('a cashier over the credit limit is refused, with no override offered', (
    tester,
  ) async {
    await (db.update(db.customers)..where((t) => t.id.equals(janeDoe.id))).write(
      const CustomersCompanion(creditLimit: Value(30)),
    );

    await pumpScreen(tester);
    await reviewOrder(tester);
    await chooseCustomer(tester, 'Jane');
    await tester.enterText(find.widgetWithText(TextField, 'Amount paid now'), '0');
    await tester.pumpAndSettle();
    await completeSale(tester);

    expect(find.textContaining('over their credit limit'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Override and complete'), findsNothing);
    expect(find.text('A manager can approve this.'), findsOneWidget);
    expect(await db.select(db.sales).get(), isEmpty);

    await disposeScreen(tester);
  });

  testWidgets('a manager can override the credit limit and complete the sale', (tester) async {
    await (db.update(db.customers)..where((t) => t.id.equals(janeDoe.id))).write(
      const CustomersCompanion(creditLimit: Value(30)),
    );

    await pumpScreen(tester, as: manager);
    await reviewOrder(tester);
    await chooseCustomer(tester, 'Jane');
    await tester.enterText(find.widgetWithText(TextField, 'Amount paid now'), '0');
    await tester.pumpAndSettle();
    await completeSale(tester);

    // Refused first — the override is offered against that refusal rather
    // than standing on the screen as a way to skip the check.
    expect(find.textContaining('over their credit limit'), findsOneWidget);
    expect(await db.select(db.sales).get(), isEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Override and complete'));
    await tester.pumpAndSettle();

    final sale = await db.select(db.sales).getSingle();
    expect(sale.total, 70);
    final customer = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(janeDoe.id))).getSingle();
    expect(customer.currentBalance, 70, reason: 'the whole total went on account');

    await disposeScreen(tester);
  });

  testWidgets('holding an order clears it, and resuming brings it back', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Soda'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Hold order'));
    await tester.pumpAndSettle();

    expect(find.text('Tap a product to start the order.'), findsOneWidget);

    await tester.tap(find.byTooltip('Held orders'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Resume'));
    await tester.pumpAndSettle();

    expect(find.text('Tap a product to start the order.'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Review order'), findsOneWidget);

    await disposeScreen(tester);
  });
}
