import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/products/presentation/screens/product_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late int drinksCategoryId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    drinksCategoryId = (await db.into(db.categories).insertReturning(
      CategoriesCompanion.insert(
        uuid: 'cat-drinks',
        name: 'Drinks',
        createdAt: DateTime.now(),
      ),
    )).id;
    final snacksCategoryId = (await db.into(db.categories).insertReturning(
      CategoriesCompanion.insert(
        uuid: 'cat-snacks',
        name: 'Snacks',
        createdAt: DateTime.now(),
      ),
    )).id;

    Future<void> product({
      required String name,
      String? sku,
      int? categoryId,
      double stock = 10,
      double reorderLevel = 5,
      double costPrice = 50,
      double sellingPrice = 80,
    }) {
      return db.into(db.products).insert(
        ProductsCompanion.insert(
          uuid: 'prod-$name',
          name: name,
          sku: Value(sku),
          categoryId: Value(categoryId),
          stock: Value(stock),
          reorderLevel: Value(reorderLevel),
          costPrice: Value(costPrice),
          sellingPrice: Value(sellingPrice),
          minSellingPrice: Value(sellingPrice),
          createdAt: DateTime.now(),
        ),
      );
    }

    await product(
      name: 'Soda',
      sku: 'SODA-1',
      categoryId: drinksCategoryId,
      stock: 20,
      reorderLevel: 5,
    );
    await product(
      name: 'Juice',
      sku: 'JUICE-1',
      categoryId: drinksCategoryId,
      stock: 2,
      reorderLevel: 5, // low stock
    );
    await product(
      name: 'Chips',
      sku: 'CHIP-1',
      categoryId: snacksCategoryId,
      stock: 15,
      reorderLevel: 5,
    );
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ProductListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Drift's stream-query cleanup schedules a zero-duration Timer when a
  // watch() subscription is cancelled. Disposing the ProviderScope here
  // (rather than leaving it to flutter_test's automatic end-of-test
  // teardown, which runs its "no pending timers" check before addTearDown
  // callbacks fire) and pumping with an explicit duration — a bare pump()
  // doesn't elapse the fake clock at all — lets that timer fire before that
  // check runs.
  void productListTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      await pumpScreen(tester);
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  }

  productListTest('lists all active products with their columns', (tester) async {
    expect(find.text('Soda'), findsOneWidget);
    expect(find.text('Juice'), findsOneWidget);
    expect(find.text('Chips'), findsOneWidget);
    expect(find.text('SODA-1'), findsOneWidget);
    expect(find.text('Drinks'), findsWidgets);
    expect(find.text('Snacks'), findsWidgets);
  });

  productListTest('search filters as you type by name', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'jui');
    await tester.pumpAndSettle();

    expect(find.text('Juice'), findsOneWidget);
    expect(find.text('Soda'), findsNothing);
    expect(find.text('Chips'), findsNothing);
  });

  productListTest('search matches SKU too', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'chip-1');
    await tester.pumpAndSettle();

    expect(find.text('Chips'), findsOneWidget);
    expect(find.text('Soda'), findsNothing);
  });

  productListTest('category filter narrows the list', (tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<int?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snacks').last);
    await tester.pumpAndSettle();

    expect(find.text('Chips'), findsOneWidget);
    expect(find.text('Soda'), findsNothing);
    expect(find.text('Juice'), findsNothing);
  });

  productListTest('low stock only filter keeps just low-stock products', (tester) async {
    await tester.tap(find.widgetWithText(FilterChip, 'Low stock only'));
    await tester.pumpAndSettle();

    expect(find.text('Juice'), findsOneWidget);
    expect(find.text('Soda'), findsNothing);
    expect(find.text('Chips'), findsNothing);
  });

  productListTest('shows an empty state when nothing matches', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'nonexistent product');
    await tester.pumpAndSettle();

    expect(find.text('No products match your filters.'), findsOneWidget);
  });
}
