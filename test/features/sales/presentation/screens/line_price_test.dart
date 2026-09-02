import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/sales/presentation/screens/sale_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hardware counter haggles, so each line's price can be typed over. The
/// product's floor still holds — these check that both halves are true.
void main() {
  late DukaDatabase db;
  late User cashier;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'PVC pipe',
        costPrice: const Value(320),
        sellingPrice: const Value(420),
        // Won't go below this, whatever is typed.
        minSellingPrice: const Value(380),
        stock: const Value(50),
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

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => cashier),
        ],
        child: const MaterialApp(home: SaleScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('PVC pipe'));
    await tester.pumpAndSettle();
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  testWidgets('a line starts at the selling price and shows its floor', (tester) async {
    await pumpScreen(tester);

    final priceField = find.widgetWithText(TextField, 'Unit price');
    expect(tester.widget<TextField>(priceField).controller!.text, '420.00');
    expect(find.text('Min 380.00'), findsOneWidget);
    expect(find.text('Order total'), findsOneWidget);
    expect(find.text('420.00'), findsWidgets);

    await disposeScreen(tester);
  });

  testWidgets('typing a lower price is accepted and moves the total', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Unit price'), '400');
    await tester.pumpAndSettle();

    // The order total follows the negotiated price, not the shelf price.
    expect(find.text('400.00'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Review order'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Complete sale'));
    await tester.pumpAndSettle();

    final sale = await db.select(db.sales).getSingle();
    expect(sale.total, 400, reason: 'the sale is recorded at the price agreed');

    await disposeScreen(tester);
  });

  testWidgets('a price under the floor is flagged, and the sale is refused', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Unit price'), '300');
    await tester.pumpAndSettle();

    // Flagged on the line while the order is being built…
    expect(find.text('Min 380.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Review order'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Complete sale'));
    await tester.pumpAndSettle();

    // …and refused outright at payment, by the repository's own check.
    expect(find.textContaining('below its minimum selling price'), findsOneWidget);
    expect(await db.select(db.sales).get(), isEmpty);

    await disposeScreen(tester);
  });
}
