import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/purchases/presentation/screens/purchase_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late int supplierAId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));

    supplierAId = (await db.into(db.suppliers).insertReturning(
      SuppliersCompanion.insert(uuid: 'sup-a', name: 'Acme Traders', createdAt: DateTime.now()),
    )).id;
    final supplierBId = (await db.into(db.suppliers).insertReturning(
      SuppliersCompanion.insert(uuid: 'sup-b', name: 'Coastal Foods', createdAt: DateTime.now()),
    )).id;

    final userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'manager',
        passwordHash: 'hash',
        fullName: 'Manager One',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    )).id;

    Future<void> purchase({
      required String uuid,
      String? referenceNumber,
      required int supplierId,
      required double total,
      required double amountPaid,
      required String paymentStatus,
    }) {
      return db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          uuid: uuid,
          referenceNumber: Value(referenceNumber),
          supplierId: supplierId,
          userId: userId,
          total: Value(total),
          amountPaid: Value(amountPaid),
          status: const Value('received'),
          paymentStatus: Value(paymentStatus),
          createdAt: DateTime(2026, 3, 4),
        ),
      );
    }

    await purchase(
      uuid: 'p1',
      referenceNumber: 'PO-1001',
      supplierId: supplierAId,
      total: 500,
      amountPaid: 500,
      paymentStatus: 'paid',
    );
    await purchase(
      uuid: 'p2',
      referenceNumber: 'PO-1002',
      supplierId: supplierBId,
      total: 300,
      amountPaid: 100,
      paymentStatus: 'partial',
    );
    await purchase(
      uuid: 'p3',
      referenceNumber: 'PO-1003',
      supplierId: supplierAId,
      total: 200,
      amountPaid: 0,
      paymentStatus: 'unpaid',
    );
  });

  tearDown(() => db.close());

  void purchaseListTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(description, (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MaterialApp(home: PurchaseListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await body(tester);

      // See product_list_screen_test.dart for why this matters: drift's
      // stream cleanup needs to run (and be pumped with an explicit
      // duration) before flutter_test's own end-of-test teardown checks
      // for pending timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    });
  }

  purchaseListTest('lists purchases with reference, supplier, total, amount paid and status', (
    tester,
  ) async {
    expect(find.text('PO-1001'), findsOneWidget);
    expect(find.text('Acme Traders'), findsWidgets);
    expect(find.text('500.00'), findsWidgets);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Partially paid'), findsOneWidget);
    expect(find.text('Credit'), findsOneWidget);
  });

  purchaseListTest('search filters by PO reference', (tester) async {
    await tester.enterText(find.byType(TextField).first, '1002');
    await tester.pumpAndSettle();

    expect(find.text('PO-1002'), findsOneWidget);
    expect(find.text('PO-1001'), findsNothing);
  });

  purchaseListTest('search filters by supplier name', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'coastal');
    await tester.pumpAndSettle();

    expect(find.text('PO-1002'), findsOneWidget);
    expect(find.text('PO-1001'), findsNothing);
    expect(find.text('PO-1003'), findsNothing);
  });

  purchaseListTest('status filter narrows to Credit purchases', (tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credit').last);
    await tester.pumpAndSettle();

    expect(find.text('PO-1003'), findsOneWidget);
    expect(find.text('PO-1001'), findsNothing);
    expect(find.text('PO-1002'), findsNothing);
  });

  purchaseListTest('shows an empty state when nothing matches', (tester) async {
    await tester.enterText(find.byType(TextField).first, 'nonexistent po');
    await tester.pumpAndSettle();

    expect(find.text('No purchases match your filters.'), findsOneWidget);
  });
}
