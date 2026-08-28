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

  Future<CreditTransaction> recordPayment({
    required int customerId,
    required double amount,
    String? notes,
  });

  Stream<List<CreditTransaction>> watchTransactionsForCustomer(
    int customerId,
  );

  Future<double> getCustomerBalance(int customerId);
}
