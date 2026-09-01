import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/suppliers/presentation/screens/supplier_form_screen.dart';
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

  Future<void> pumpForm(WidgetTester tester, {required User as}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => as),
        ],
        child: const MaterialApp(home: SupplierFormScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a manager can add the supplier the goods-receipt picker reads',
      (tester) async {
    await pumpForm(tester, as: manager);

    await tester.enterText(
      find.widgetWithText(TextField, 'Supplier name'),
      'Nyeri Wholesalers',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone (optional)'),
      '0722 114 093',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add supplier'));
    await tester.pumpAndSettle();

    final supplier = await db.select(db.suppliers).getSingle();
    expect(supplier.name, 'Nyeri Wholesalers');
    expect(supplier.phone, '0722 114 093');
    expect(supplier.email, isNull, reason: 'blank optional fields stay null');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a cashier is refused, and nothing is saved', (tester) async {
    await pumpForm(tester, as: cashier);

    await tester.enterText(find.widgetWithText(TextField, 'Supplier name'), 'Anywhere');
    await tester.tap(find.widgetWithText(FilledButton, 'Add supplier'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Only a manager'), findsOneWidget);
    expect(await db.select(db.suppliers).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
