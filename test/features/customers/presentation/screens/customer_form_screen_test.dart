import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

User _userWithRole(String role) {
  return User(
    id: 1,
    uuid: 'u1',
    username: 'jdoe',
    passwordHash: 'hash',
    fullName: 'Jane Doe',
    role: role,
    isActive: true,
    createdAt: DateTime(2026),
  );
}

void main() {
  late DukaDatabase db;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
  });

  tearDown(() => db.close());

  final navigatorKey = GlobalKey<NavigatorState>();

  // CustomerFormScreen calls Navigator.pop() on success, so it needs a real
  // route underneath it (pushed, not the app's only route) or that pop
  // would have nowhere to go.
  Future<void> pumpScreen(WidgetTester tester, User user) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserProvider.overrideWith((ref) => user),
        ],
        child: MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('adds a customer and pops', (tester) async {
    await pumpScreen(tester, _userWithRole('manager'));

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Jane');
    await tester.enterText(find.widgetWithText(TextField, 'Credit limit'), '500');

    await tester.tap(find.widgetWithText(FilledButton, 'Add customer'));
    await tester.pumpAndSettle();

    final customer = await db.select(db.customers).getSingle();
    expect(customer.name, 'Jane');
    expect(customer.creditLimit, 500);

    expect(find.byType(CustomerFormScreen), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('an empty name shows an error and saves nothing', (tester) async {
    await pumpScreen(tester, _userWithRole('manager'));

    await tester.tap(find.widgetWithText(FilledButton, 'Add customer'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a name.'), findsOneWidget);
    expect(await db.select(db.customers).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });

  testWidgets('a cashier sees a permission error and saves nothing', (tester) async {
    await pumpScreen(tester, _userWithRole('cashier'));

    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Jane');
    await tester.tap(find.widgetWithText(FilledButton, 'Add customer'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Only a manager"), findsOneWidget);
    expect(await db.select(db.customers).get(), isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
