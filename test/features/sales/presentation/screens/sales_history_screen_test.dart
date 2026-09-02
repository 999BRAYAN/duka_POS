import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/presentation/screens/sales_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voiding is finally reachable from a screen. The data layer's behaviour is
/// covered in the repository tests; these check that the screen gates it to a
/// manager, insists on a reason, and actually reverses the sale.
void main() {
  late DukaDatabase db;
  late User manager;
  late User cashier;
  late Customer jane;
  late int productId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Gate valve',
        sellingPrice: const Value(850),
        stock: const Value(10),
        createdAt: DateTime.now(),
      ),
    )).id;

    manager = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'amina',
        passwordHash: 'hash',
        fullName: 'Amina Wanjiru',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    );
    cashier = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-2',
        username: 'peter',
        passwordHash: 'hash',
        fullName: 'Peter Otieno',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
    jane = await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane',
        creditLimit: const Value(5000),
        createdAt: DateTime.now(),
      ),
    );

    // A sale left partly unpaid, so voiding has both stock and debt to undo.
    final credit = CreditRepositoryImpl(db);
    final sales = SaleRepositoryImpl(db, StockMovementRepositoryImpl(db), credit);
    await sales.completeSale(
      cart: [CartLine(productId: productId, name: 'Gate valve', price: 850, quantity: 2)],
      customerId: jane.id,
      userId: manager.id,
      paymentMethod: 'credit',
      amountPaid: 700,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester, {required User as}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => as),
        ],
        child: const MaterialApp(home: SalesHistoryScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('a cashier sees the sale but cannot void it', (tester) async {
    await pumpScreen(tester, as: cashier);

    expect(find.text('INV-000001'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Void'), findsNothing);
    expect(find.text('manager only'), findsOneWidget);

    await disposeScreen(tester);
  });

  testWidgets('a manager must give a reason before the void goes through', (tester) async {
    await pumpScreen(tester, as: manager);

    // The row scrolls sideways on a narrower window, so bring the action
    // into view rather than tapping where it merely might be.
    final voidButton = find.widgetWithText(TextButton, 'Void');
    await tester.ensureVisible(voidButton);
    await tester.pumpAndSettle();
    await tester.tap(voidButton);
    await tester.pumpAndSettle();

    // Confirming with an empty reason is refused by the dialog itself.
    await tester.tap(find.widgetWithText(FilledButton, 'Void sale'));
    await tester.pumpAndSettle();

    expect(find.text('Say why this sale is being voided.'), findsOneWidget);
    expect((await db.select(db.sales).getSingle()).status, 'completed');

    await disposeScreen(tester);
  });

  testWidgets('voiding returns the stock and clears the debt', (tester) async {
    await pumpScreen(tester, as: manager);

    // The row scrolls sideways on a narrower window, so bring the action
    // into view rather than tapping where it merely might be.
    final voidButton = find.widgetWithText(TextButton, 'Void');
    await tester.ensureVisible(voidButton);
    await tester.pumpAndSettle();
    await tester.tap(voidButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Reason'), 'Wrong size rung up');
    await tester.tap(find.widgetWithText(FilledButton, 'Void sale'));
    await tester.pumpAndSettle();

    final sale = await db.select(db.sales).getSingle();
    expect(sale.status, 'void');
    expect(sale.voidReason, 'Wrong size rung up');
    expect(sale.voidedByUserId, manager.id, reason: 'who voided it is on the record');

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 10, reason: 'both valves came back');

    final customer = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(jane.id))).getSingle();
    expect(customer.currentBalance, 0, reason: 'the 1,000 owing was reversed');

    await disposeScreen(tester);
  });
}
