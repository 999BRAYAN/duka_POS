import 'package:flutter/material.dart';

import '../../domain/exceptions.dart';

/// Asks the user to confirm saving a product below cost. Returns true if
/// they chose to save anyway, false if they cancelled or dismissed it.
Future<bool> showPriceBelowCostDialog(
  BuildContext context, {
  required double costPrice,
  required double minSellingPrice,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Selling below cost'),
      content: Text(
        'The minimum selling price (${minSellingPrice.toStringAsFixed(2)}) '
        'is below the cost price (${costPrice.toStringAsFixed(2)}). '
        'Save anyway?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save anyway'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Runs [save] with the override left off; if it rejects the price with a
/// [PriceBelowCostException], asks the user via [showPriceBelowCostDialog]
/// and retries with the override only if they confirm. Returns the saved
/// value, or null if the user cancelled.
Future<T?> saveProductWithPriceConfirmation<T>(
  BuildContext context,
  Future<T> Function({required bool confirmPriceBelowCost}) save,
) async {
  try {
    return await save(confirmPriceBelowCost: false);
  } on PriceBelowCostException catch (e) {
    if (!context.mounted) return null;
    final confirmed = await showPriceBelowCostDialog(
      context,
      costPrice: e.costPrice,
      minSellingPrice: e.minSellingPrice,
    );
    if (!confirmed) return null;
    return save(confirmPriceBelowCost: true);
  }
}
