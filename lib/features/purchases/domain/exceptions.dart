/// Thrown by [PurchaseRepository.markPurchaseReceived] or `cancelPurchase`
/// when the purchase's current status makes the requested transition
/// invalid (e.g. cancelling one that's already received).
class InvalidPurchaseStatusException implements Exception {
  const InvalidPurchaseStatusException(this.message);

  final String message;

  @override
  String toString() => message;
}
