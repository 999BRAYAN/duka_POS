import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_ledger_repository.dart';

class CustomerLedgerRepositoryImpl implements CustomerLedgerRepository {
  CustomerLedgerRepositoryImpl(this._db);

  final DukaDatabase _db;

  @override
  Future<List<CustomerLedgerEntry>> getLedgerForCustomer(int customerId) async {
    // One table, one query. Every movement of Customers.currentBalance now
    // goes through CreditRepository and leaves a row here — a sale that
    // left money owing (CHARGE), money collected (PAYMENT), or a voided
    // sale's charge coming back off (REVERSAL). This used to merge the
    // sales table in as well, because sales wrote the balance directly and
    // left no row of their own to read.
    final transactions = await (_db.select(_db.creditTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            // Rows written inside one transaction can share a millisecond,
            // so id breaks the tie and keeps the running balance stable.
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();

    // Invoice numbers for the CHARGE/REVERSAL rows that carry a saleId, so
    // a statement line reads "INV-000123" rather than a bare row id.
    final saleIds = transactions.map((t) => t.saleId).nonNulls.toSet();
    final invoiceNumbers = <int, String>{};
    if (saleIds.isNotEmpty) {
      final sales = await (_db.select(
        _db.sales,
      )..where((t) => t.id.isIn(saleIds))).get();
      for (final sale in sales) {
        invoiceNumbers[sale.id] = sale.invoiceNumber;
      }
    }

    var runningBalance = 0.0;
    return [
      for (final transaction in transactions)
        () {
          final type = switch (transaction.type) {
            'CHARGE' => CustomerLedgerEntryType.creditSale,
            'REVERSAL' => CustomerLedgerEntryType.reversal,
            _ => CustomerLedgerEntryType.payment,
          };
          runningBalance += switch (type) {
            CustomerLedgerEntryType.creditSale => transaction.amount,
            CustomerLedgerEntryType.payment => -transaction.amount,
            CustomerLedgerEntryType.reversal => -transaction.amount,
          };
          // Never let the running total go below zero: the balance writes
          // themselves are floored, so a reversal or payment against an
          // already-settled debt must not push this line negative either.
          if (runningBalance < 0) runningBalance = 0;

          return CustomerLedgerEntry(
            date: transaction.createdAt,
            type: type,
            reference: switch (type) {
              CustomerLedgerEntryType.payment =>
                transaction.method ?? 'unspecified',
              _ => invoiceNumbers[transaction.saleId] ?? 'adjustment',
            },
            amount: transaction.amount,
            runningBalance: runningBalance,
          );
        }(),
    ];
  }
}
