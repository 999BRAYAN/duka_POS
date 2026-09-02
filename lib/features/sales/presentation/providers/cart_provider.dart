import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The in-progress sale cart. Deliberately independent of
/// ProductRepository/CustomerRepository/SaleRepository — callers hand it
/// plain values (productId, name, price), so it doesn't know or care where
/// they came from. That keeps it usable (and testable) before any of those
/// repositories are wired into a screen, and means checkout — which does
/// depend on those repositories — is a separate concern layered on top of
/// this, not part of it.
class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => const [];

  /// Adds [quantity] of a product to the cart, or increases the existing
  /// line's quantity if it's already there. [name] and [price] are
  /// snapshotted now; see the class doc on [CartLine] for why cost isn't
  /// captured here.
  void addProduct({
    required int productId,
    required String name,
    required double price,
    double quantity = 1,
  }) {
    final index = state.indexWhere((line) => line.productId == productId);
    if (index == -1) {
      state = [
        ...state,
        CartLine(productId: productId, name: name, price: price, quantity: quantity),
      ];
      return;
    }

    final existing = state[index];
    state = [
      for (var i = 0; i < state.length; i++)
        if (i == index) existing.copyWith(quantity: existing.quantity + quantity) else state[i],
    ];
  }

  /// Sets a line's quantity directly. Removes the line if [quantity] is
  /// zero or negative.
  void setQuantity(int productId, double quantity) {
    if (quantity <= 0) {
      removeLine(productId);
      return;
    }
    state = [
      for (final line in state)
        if (line.productId == productId) line.copyWith(quantity: quantity) else line,
    ];
  }

  /// Sets what this line will actually sell for.
  ///
  /// A hardware counter haggles: a plumber buying forty lengths does not pay
  /// the shelf price. The floor still holds — SaleRepository.completeSale
  /// checks every line against its product's minSellingPrice and refuses the
  /// whole sale below it, so this can be offered freely without it becoming
  /// a way to give stock away.
  void setPrice(int productId, double price) {
    if (price < 0) return;
    state = [
      for (final line in state)
        if (line.productId == productId) line.copyWith(price: price) else line,
    ];
  }

  void removeLine(int productId) {
    state = state.where((line) => line.productId != productId).toList();
  }

  void clear() => state = const [];

  /// Wholesale-replaces the cart, e.g. when resuming a held sale.
  void replaceAll(List<CartLine> lines) => state = List<CartLine>.of(lines);
}

final cartProvider = NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final cartSubtotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold<double>(0, (sum, line) => sum + line.lineTotal);
});

/// Total units across all lines (not distinct line count) — the number a
/// cart badge would show.
final cartItemCountProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold<double>(0, (sum, line) => sum + line.quantity);
});
