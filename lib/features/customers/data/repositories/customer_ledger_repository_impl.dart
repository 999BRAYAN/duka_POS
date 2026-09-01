import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_ledger_repository.dart';

class CustomerLedgerRepositoryImpl implements CustomerLedgerRepository {
  CustomerLedgerRepositoryImpl(this._db);

  final DukaDatabase _db;

  @override
  Future<List<CustomerLedgerEntry>> getLedgerForCustomer(int customerId) async {
    // Only sales left with a balance due count as "on credit" here — the
    // same total > amountPaid condition SaleRepository.completeSale checks
    // against the customer's creditLimit, regardless of what
    // paymentMethod is literally labeled. A fully-paid sale never touches
    // Customers.currentBalance, so it has no place in this ledger.
    //
    // Void sales are excluded because voidSale now reverses its charge
    // against Customers.currentBalance. This filter and that reversal are
    // one decision: leave a void sale in the ledger and the running
    // balance stops reconciling with the customer's stored balance by
    // exactly the voided amount.
    final sales = await (_db.select(_db.sales)..where(
      (t) =>
          t.customerId.equals(customerId) &
          t.total.isBiggerThan(t.amountPaid) &
          t.status.equals('void').not(),
    )).get();

    final payments = await (_db.select(_db.creditTransactions)..where(
      (t) => t.customerId.equals(customerId) & t.type.equals('PAYMENT'),
    )).get();

    final postings = [
      for (final sale in sales)
        (
          date: sale.createdAt,
          type: CustomerLedgerEntryType.creditSale,
          reference: sale.invoiceNumber,
          amount: sale.total - sale.amountPaid,
        ),
      for (final payment in payments)
        (
          date: payment.createdAt,
          type: CustomerLedgerEntryType.payment,
          reference: payment.method ?? 'unspecified',
          amount: payment.amount,
        ),
    ]..sort((a, b) => a.date.compareTo(b.date));

    var runningBalance = 0.0;
    return [
      for (final posting in postings)
        CustomerLedgerEntry(
          date: posting.date,
          type: posting.type,
          reference: posting.reference,
          amount: posting.amount,
          runningBalance: runningBalance += switch (posting.type) {
            CustomerLedgerEntryType.creditSale => posting.amount,
            CustomerLedgerEntryType.payment => -posting.amount,
          },
        ),
    ];
  }
}
