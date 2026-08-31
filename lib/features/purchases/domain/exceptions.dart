/// Thrown by [PurchaseRepository.markPurchaseReceived] or `cancelPurchase`
/// when the purchase's current status makes the requested transition
/// invalid (e.g. cancelling one that's already received).
class InvalidPurchaseStatusException implements Exception {
  const InvalidPurchaseStatusException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown by [PurchaseRepository.receiveStock] when [paymentStatus] isn't
/// one of the values Purchases.paymentStatus supports ('paid', 'partial',
/// 'unpaid').
class InvalidPaymentStatusException implements Exception {
  const InvalidPaymentStatusException(this.message);

  final String message;

  @override
  String toString() => message;
}
