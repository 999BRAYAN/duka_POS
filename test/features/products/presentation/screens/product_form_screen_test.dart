import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/products/presentation/screens/product_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late User manager;
  late User cashier;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    manager = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-manager',
        username: 'amina',
        passwordHash: 'hash',
        fullName: 'Amina Wanjiru',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    );
    cashier = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-cashier',
        username: 'peter',
        passwordHash: 'hash',
        fullName: 'Peter Otieno',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpForm(WidgetTester tester, {required User as, Product? product}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => as),
        ],
        child: MaterialApp(home: ProductFormScreen(product: product)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> disposeForm(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> tapSave(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('a manager can add a product with opening stock', (tester) async {
    await pumpForm(tester, as: manager);

    await tester.enterText(
      find.widgetWithText(TextField, 'Product name'),
      'Maize flour 2kg',
    );
    await tester.enterText(find.widgetWithText(TextField, 'SKU (optional)'), 'MAI-2KG');
    await tester.enterText(find.widgetWithText(TextField, 'Cost price'), '145');
    await tester.enterText(find.widgetWithText(TextField, 'Selling price'), '180');
    await tester.enterText(find.widgetWithText(TextField, 'Opening stock'), '24');
    await tapSave(tester, 'Add product');

    final product = await db.select(db.products).getSingle();
    expect(product.name, 'Maize flour 2kg');
    expect(product.sku, 'MAI-2KG');
    expect(product.costPrice, 145);
    expect(product.sellingPrice, 180);
    expect(product.stock, 24);
    expect(
      product.minSellingPrice,
      180,
      reason: 'left blank, the floor is the selling price, not zero',
    );

    await disposeForm(tester);
  });

  testWidgets('a cashier is refused, and nothing is saved', (tester) async {
    await pumpForm(tester, as: cashier);

    await tester.enterText(find.widgetWithText(TextField, 'Product name'), 'Sugar 1kg');
    await tester.enterText(find.widgetWithText(TextField, 'Cost price'), '155');
    await tester.enterText(find.widgetWithText(TextField, 'Selling price'), '190');
    await tapSave(tester, 'Add product');

    expect(find.textContaining('Only a manager'), findsOneWidget);
    expect(await db.select(db.products).get(), isEmpty);

    await disposeForm(tester);
  });

  testWidgets(
    'a floor below cost asks for confirmation, and saves nothing if refused',
    (tester) async {
      await pumpForm(tester, as: manager);

      await tester.enterText(find.widgetWithText(TextField, 'Product name'), 'Rice 1kg');
      await tester.enterText(find.widgetWithText(TextField, 'Cost price'), '130');
      await tester.enterText(find.widgetWithText(TextField, 'Selling price'), '175');
      await tester.enterText(
        find.widgetWithText(TextField, 'Lowest price you will accept'),
        '100',
      );
      await tapSave(tester, 'Add product');

      expect(find.text('Selling below cost'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await db.select(db.products).get(), isEmpty);

      // Confirming saves it.
      await tapSave(tester, 'Add product');
      expect(find.text('Selling below cost'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save anyway'));
      await tester.pumpAndSettle();

      final product = await db.select(db.products).getSingle();
      expect(product.minSellingPrice, 100);

      await disposeForm(tester);
    },
  );

  testWidgets('editing changes prices but never stock', (tester) async {
    final existing = await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Sugar 1kg',
        costPrice: const Value(155),
        sellingPrice: const Value(190),
        minSellingPrice: const Value(190),
        stock: const Value(18),
        createdAt: DateTime.now(),
      ),
    );

    await pumpForm(tester, as: manager, product: existing);

    // Stock is not offered while editing: recordMovement is the only writer.
    expect(find.widgetWithText(TextField, 'Opening stock'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Selling price'), '200');
    await tapSave(tester, 'Save changes');

    final updated = await db.select(db.products).getSingle();
    expect(updated.sellingPrice, 200);
    expect(updated.stock, 18, reason: 'editing a product must not move stock');

    await disposeForm(tester);
  });
}
