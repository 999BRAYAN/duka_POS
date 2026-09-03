import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/core/security/password_hasher.dart';
import 'package:duka_pos/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
  });
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  // See the matching comment in product_list_screen_test.dart: dispose the
  // ProviderScope (and its drift streams) under our own pump instead of
  // flutter_test's automatic teardown, then pump with an explicit duration
  // so drift's cleanup Timer fires before the "no pending timers" check.
  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }

  Future<void> addManager() async {
    await db.into(db.users).insert(
      UsersCompanion.insert(
        uuid: 'user-manager',
        username: 'amina',
        passwordHash: PasswordHasher.hash('duka2026'),
        fullName: 'Amina Wanjiru',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> addCashier() async {
    await db.into(db.users).insert(
      UsersCompanion.insert(
        uuid: 'user-cashier',
        username: 'brian',
        passwordHash: PasswordHasher.hash('cashier2026'),
        fullName: 'Brian Otieno',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
  }

  testWidgets('a shop with no accounts opens the first-run setup', (tester) async {
    await pumpApp(tester);

    expect(find.text('Set up this till'), findsOneWidget);
    expect(
      find.text('Products'),
      findsNothing,
      reason: 'the till must not be reachable before an account exists',
    );

    await disposeApp(tester);
  });

  testWidgets('creating the manager signs them in and opens the till', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Amina Wanjiru');
    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'amina');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'duka2026');
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'duka2026',
    );
    // The form is taller than the 600px test viewport; it scrolls in a real
    // window, so scroll to the button rather than pretending it is visible.
    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.pumpAndSettle();
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsWidgets);

    final stored = await db.select(db.users).getSingle();
    expect(stored.role, 'manager');
    expect(
      PasswordHasher.isHashed(stored.passwordHash),
      isTrue,
      reason: 'the password is never stored as typed',
    );
    expect(stored.passwordHash, isNot(contains('duka2026')));

    await disposeApp(tester);
  });

  testWidgets('a shop with an account opens the sign-in screen', (tester) async {
    await addManager();
    await pumpApp(tester);

    expect(find.text('Sign in to open the till'), findsOneWidget);
    expect(find.text('Products'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('the right password opens the till, a wrong one does not', (tester) async {
    await addManager();
    await pumpApp(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Username'), 'amina');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.textContaining("don't match"), findsOneWidget);
    expect(find.text('Products'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'duka2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsWidgets);

    await disposeApp(tester);
  });

  testWidgets('signing out closes the till again', (tester) async {
    await addManager();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final user = await db.select(db.users).getSingle();
    container.read(currentUserProvider.notifier).state = user;

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsWidgets);

    container.read(currentUserProvider.notifier).state = null;
    await tester.pumpAndSettle();

    expect(find.text('Sign in to open the till'), findsOneWidget);
    expect(find.text('Products'), findsNothing);

    await disposeApp(tester);
  });

  testWidgets('switching user signs in as someone else without leaving the app', (tester) async {
    await addManager();
    await addCashier();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final manager = (await db.select(
      db.users,
    ).get()).firstWhere((u) => u.role == 'manager');
    container.read(currentUserProvider.notifier).state = manager;

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsWidgets);

    // Below NavRail.persistentFrom, the drawer is reached through the
    // hamburger rather than sitting on the page already.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Switch user'));
    await tester.pumpAndSettle();

    // The signed-in manager must not appear as an option to switch to.
    expect(find.text('Amina Wanjiru'), findsNothing);
    expect(find.text('Brian Otieno'), findsOneWidget);

    await tester.tap(find.text('Brian Otieno'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Switch'));
    await tester.pumpAndSettle();

    expect(find.textContaining("don't match"), findsOneWidget);
    expect(container.read(currentUserProvider)?.fullName, 'Amina Wanjiru');

    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'cashier2026');
    await tester.tap(find.widgetWithText(FilledButton, 'Switch'));
    await tester.pumpAndSettle();

    expect(container.read(currentUserProvider)?.fullName, 'Brian Otieno');
    // Still in the app, on the same screen — no sign-out/reload round trip.
    expect(find.text('Sign in to open the till'), findsNothing);
    expect(find.text('Products'), findsWidgets);

    await disposeApp(tester);
  });
}
