/// Thrown by [SaleRepository.createSale] when a line's effective per-unit
/// price — after its own discount and its proportional share of the cart-
/// level discount — falls below that product's minSellingPrice floor.
/// Checked in the repository itself (not just the cart/checkout UI), so it
/// can't be bypassed by a caller that skips client-side validation.
class PriceBelowFloorException implements Exception {
  const PriceBelowFloorException({
    required this.productName,
    required this.effectivePrice,
    required this.minSellingPrice,
  });

  final String productName;
  final double effectivePrice;
  final double minSellingPrice;

  @override
  String toString() =>
      "'$productName' would sell at ${effectivePrice.toStringAsFixed(2)} "
      'after discount, below its minimum selling price of '
      '${minSellingPrice.toStringAsFixed(2)}.';
}

/// Thrown by [SaleRepository.completeSale] when a product's current stock
/// — re-read at checkout, not the possibly-stale amount the cart was built
/// against — can't cover the requested quantity.
class InsufficientStockException implements Exception {
  const InsufficientStockException({
    required this.productName,
    required this.requested,
    required this.available,
  });

  final String productName;
  final double requested;
  final double available;

  @override
  String toString() =>
      "Only ${available.toStringAsFixed(2)} of '$productName' left in "
      'stock, but ${requested.toStringAsFixed(2)} were requested.';
}

/// Thrown by [SaleRepository.completeSale] when paymentMethod is 'credit'
/// but no customer was given — there's no one to extend credit to, and
/// nothing whose creditLimit could be checked.
class CustomerRequiredForCreditException implements Exception {
  const CustomerRequiredForCreditException();

  @override
  String toString() => "A customer is required for payment method 'credit'.";
}

/// Thrown by [SaleRepository.voidSale] when the sale is already void.
/// Voiding is not idempotent — it returns stock and credits the customer's
/// balance — so a second void would return the goods twice.
class SaleAlreadyVoidException implements Exception {
  const SaleAlreadyVoidException({required this.invoiceNumber});

  final String invoiceNumber;

  @override
  String toString() => 'Sale $invoiceNumber has already been voided.';
}

/// Thrown by [SaleRepository.completeSale] when a credit sale would push
/// the customer's balance past their creditLimit, and no override was
/// passed.
class CreditLimitExceededException implements Exception {
  const CreditLimitExceededException({
    required this.customerName,
    required this.wouldBeBalance,
    required this.creditLimit,
  });

  final String customerName;
  final double wouldBeBalance;
  final double creditLimit;

  @override
  String toString() =>
      "This sale would take $customerName's balance to "
      '${wouldBeBalance.toStringAsFixed(2)}, over their credit limit of '
      '${creditLimit.toStringAsFixed(2)}.';
}
