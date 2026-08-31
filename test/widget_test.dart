import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots into the product list screen', (tester) async {
    final db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Products'), findsWidgets);
    expect(find.text('No products match your filters.'), findsOneWidget);

    // See the matching comment in product_list_screen_test.dart: dispose
    // the ProviderScope (and its drift streams) under our own pump instead
    // of flutter_test's automatic end-of-test teardown, then pump with an
    // explicit duration so drift's cleanup Timer fires before the "no
    // pending timers" check (a bare pump() doesn't elapse the fake clock).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
