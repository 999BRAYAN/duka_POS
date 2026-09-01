import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/domain/models/held_sale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sales parked mid-checkout ("hold sale"), most-recently-held last.
/// In-memory only, same as [cartProvider] — see [HeldSale]'s class doc.
class HeldSalesNotifier extends Notifier<List<HeldSale>> {
  int _nextId = 1;

  @override
  List<HeldSale> build() => const [];

  HeldSale hold({
    required List<CartLine> cart,
    required int? customerId,
    required String? customerName,
    required String paymentMethod,
    required double discount,
    required double amountPaid,
  }) {
    final held = HeldSale(
      id: _nextId++,
      heldAt: DateTime.now(),
      cart: cart,
      customerId: customerId,
      customerName: customerName,
      paymentMethod: paymentMethod,
      discount: discount,
      amountPaid: amountPaid,
    );
    state = [...state, held];
    return held;
  }

  /// Removes and returns the held sale with [id], or null if it's gone
  /// (e.g. already resumed elsewhere).
  HeldSale? resume(int id) {
    final index = state.indexWhere((held) => held.id == id);
    if (index == -1) return null;
    final held = state[index];
    discard(id);
    return held;
  }

  void discard(int id) {
    state = state.where((held) => held.id != id).toList();
  }
}

final heldSalesProvider = NotifierProvider<HeldSalesNotifier, List<HeldSale>>(
  HeldSalesNotifier.new,
);
