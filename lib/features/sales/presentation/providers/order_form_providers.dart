import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The parts of an in-progress sale that aren't the cart itself.
///
/// These live in providers rather than one screen's State because the sale
/// is now built across two screens — the order is assembled on one and paid
/// for on another — and both need to read and write the same values. The
/// cart lives in cartProvider for the same reason.

/// A discount applied to the whole order, entered while building it.
final orderDiscountProvider = StateProvider<double>((ref) => 0);

/// Who the sale is for, or null for a walk-in customer paying in full.
final orderCustomerIdProvider = StateProvider<int?>((ref) => null);

/// cash, mpesa, card or credit — free-form, matching Sales.paymentMethod.
final orderPaymentMethodProvider = StateProvider<String>((ref) => 'cash');

/// How much is being paid now. Null means "the whole total", which is what
/// a walk-in sale always is; only a named customer can leave a balance.
final orderAmountPaidProvider = StateProvider<double?>((ref) => null);

/// Clears everything about the order in progress, including the cart.
void resetOrder(WidgetRef ref) {
  ref.invalidate(orderDiscountProvider);
  ref.invalidate(orderCustomerIdProvider);
  ref.invalidate(orderPaymentMethodProvider);
  ref.invalidate(orderAmountPaidProvider);
}
