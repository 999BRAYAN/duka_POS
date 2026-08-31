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
}
