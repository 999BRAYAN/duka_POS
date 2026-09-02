import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/purchases/presentation/screens/receive_stock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late int productId;
  late User manager;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    await db.into(db.suppliers).insertReturning(
      SuppliersCompanion.insert(uuid: 'sup-1', name: 'Acme Traders', createdAt: DateTime.now()),
    );
    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(uuid: 'prod-1', name: 'Soda', createdAt: DateTime.now()),
    )).id;
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

  // ReceiveStockScreen calls Navigator.pop() on success, so it needs a real
  // route underneath it (pushed, not the app's only route) or that pop
  // would have nowhere to go.
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => manager),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const ReceiveStockScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('happy path: pick supplier and product, submit, purchase is saved', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, 'Supplier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acme Traders').last);
    await tester.pumpAndSettle();

    // The product picker is a type-ahead now: type part of the name, then
    // choose from the matches it offers.
    await tester.enterText(find.widgetWithText(TextField, 'Product'), 'sod');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soda').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Qty'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Unit cost'), '30');
    await tester.pumpAndSettle();

    expect(find.text('Total: 300.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Receive stock'));
    await tester.pumpAndSettle();

    final purchases = await db.select(db.purchases).get();
    expect(purchases, hasLength(1));
    expect(purchases.single.total, 300);
    expect(purchases.single.paymentStatus, 'paid');
    expect(purchases.single.amountPaid, 300);

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 10);
    expect(product.costPrice, 30);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('shows an error and saves nothing when no supplier is selected', (tester) async {
    await pumpScreen(tester);

    // The product picker is a type-ahead now: type part of the name, then
    // choose from the matches it offers.
    await tester.enterText(find.widgetWithText(TextField, 'Product'), 'sod');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Soda').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Unit cost'), '30');

    await tester.tap(find.widgetWithText(FilledButton, 'Receive stock'));
    await tester.pumpAndSettle();

    expect(find.text('Select a supplier.'), findsOneWidget);
    expect(await db.select(db.purchases).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
