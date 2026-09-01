/// Which direction a [CustomerLedgerEntry] moves the customer's balance.
enum CustomerLedgerEntryType { creditSale, payment }

/// One row of [CustomerLedgerRepository.getLedgerForCustomer]: either a
/// sale that left a balance due (a "sale on credit", regardless of what its
/// own `Sale.paymentMethod` is literally labeled — see
/// `SaleRepository.completeSale`'s credit-limit check, which uses the same
/// convention) or a payment recorded via `CreditRepository.recordPayment`.
class CustomerLedgerEntry {
  const CustomerLedgerEntry({
    required this.date,
    required this.type,
    required this.reference,
    required this.amount,
    required this.runningBalance,
  });

  final DateTime date;
  final CustomerLedgerEntryType type;

  /// The sale's invoiceNumber for [CustomerLedgerEntryType.creditSale], or
  /// the payment method for [CustomerLedgerEntryType.payment].
  final String reference;

  /// Always positive — how much this entry moved the balance, before
  /// [type] decides the direction.
  final double amount;

  /// The customer's balance immediately after this entry, in chronological
  /// order. The last row's value is expected to equal
  /// `Customer.currentBalance`.
  final double runningBalance;
}
