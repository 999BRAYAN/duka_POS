import 'package:duka_pos/core/database/database.dart';

/// Contract for the customer credit ledger. Every charge or payment is
/// expected to also update the corresponding [Customer.currentBalance] as
/// part of the same transaction.
abstract interface class CreditRepository {
  Future<CreditTransaction> chargeCustomer({
    required int customerId,
    int? saleId,
    required double amount,
    String? notes,
  });

  /// Records a payment against [customerId]'s balance and decreases
  /// [Customer.currentBalance] to match — floored at zero, so an
  /// overpayment (or a payment recorded against a stale balance) can never
  /// leave the customer showing a negative balance. [method] is how the
  /// payment was taken (cash, mpesa, card — same free-form convention as
  /// Sales.paymentMethod).
  Future<CreditTransaction> recordPayment({
    required int customerId,
    required double amount,
    required String method,
    String? notes,
  });

  /// Reverses the charge a sale placed on [customerId] — used when that
  /// sale is voided. Decreases [Customer.currentBalance] by [amount],
  /// floored at zero for the same reason [recordPayment] floors: payments
  /// may already have been taken against this debt, and the shop never
  /// ends up owing the customer.
  Future<CreditTransaction> reverseSaleCharge({
    required int customerId,
    required int saleId,
    required double amount,
    String? notes,
  });

  Stream<List<CreditTransaction>> watchTransactionsForCustomer(
    int customerId,
  );

  Future<double> getCustomerBalance(int customerId);
}
