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

/// Thrown by [PurchaseRepository.recordPayment] when the amount isn't
/// positive, or exceeds what's still owed on the purchase.
class InvalidPurchasePaymentException implements Exception {
  const InvalidPurchasePaymentException(this.message);

  final String message;

  @override
  String toString() => message;
}
