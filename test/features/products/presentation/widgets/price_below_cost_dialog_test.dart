import 'dart:async';

import 'package:duka_pos/features/products/domain/exceptions.dart';
import 'package:duka_pos/features/products/presentation/widgets/price_below_cost_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget hostApp(VoidCallback onPressed) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: onPressed,
            child: const Text('Save'),
          ),
        ),
      ),
    );
  }

  testWidgets('confirming the dialog retries save with the override', (tester) async {
    final calls = <bool>[];
    Future<String> save({required bool confirmPriceBelowCost}) async {
      calls.add(confirmPriceBelowCost);
      if (!confirmPriceBelowCost) {
        throw const PriceBelowCostException(costPrice: 50, minSellingPrice: 40);
      }
      return 'saved';
    }

    String? result;
    await tester.pumpWidget(
      hostApp(() {}),
    );

    final context = tester.element(find.byType(ElevatedButton));
    unawaited(
      saveProductWithPriceConfirmation(context, save).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selling below cost'), findsOneWidget);
    expect(find.textContaining('40.00'), findsOneWidget);
    expect(find.textContaining('50.00'), findsOneWidget);

    await tester.tap(find.text('Save anyway'));
    await tester.pumpAndSettle();

    expect(calls, [false, true]);
    expect(result, 'saved');
  });

  testWidgets('cancelling the dialog does not retry with the override', (tester) async {
    final calls = <bool>[];
    Future<String> save({required bool confirmPriceBelowCost}) async {
      calls.add(confirmPriceBelowCost);
      if (!confirmPriceBelowCost) {
        throw const PriceBelowCostException(costPrice: 50, minSellingPrice: 40);
      }
      return 'saved';
    }

    String? result = 'unset';
    await tester.pumpWidget(hostApp(() {}));

    final context = tester.element(find.byType(ElevatedButton));
    unawaited(
      saveProductWithPriceConfirmation(context, save).then((value) => result = value),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(calls, [false]);
    expect(result, isNull);
  });

  testWidgets('save succeeding on the first try never shows a dialog', (tester) async {
    Future<String> save({required bool confirmPriceBelowCost}) async => 'saved';

    String? result;
    await tester.pumpWidget(hostApp(() {}));
    final context = tester.element(find.byType(ElevatedButton));

    result = await saveProductWithPriceConfirmation(context, save);
    await tester.pumpAndSettle();

    expect(find.text('Selling below cost'), findsNothing);
    expect(result, 'saved');
  });
}
