import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';

/// A chronological statement of everything that has moved a customer's
/// balance: every sale left with a balance due, and every payment recorded
/// against them — with a running balance so the current balance can be
/// reconciled against every posting that produced it.
abstract interface class CustomerLedgerRepository {
  Future<List<CustomerLedgerEntry>> getLedgerForCustomer(int customerId);
}
