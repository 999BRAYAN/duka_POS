import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_ledger_repository_impl.dart';
import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late CustomerLedgerRepositoryImpl ledgerRepo;
  late SaleRepositoryImpl saleRepo;
  late CreditRepositoryImpl creditRepo;
  late int customerId;
  late int userId;
  late int productId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    ledgerRepo = CustomerLedgerRepositoryImpl(db);
    creditRepo = CreditRepositoryImpl(db);
    saleRepo = SaleRepositoryImpl(db, StockMovementRepositoryImpl(db), creditRepo);

    customerId = (await db.into(db.customers).insertReturning(
      CustomersCompanion.insert(
        uuid: 'cust-1',
        name: 'Jane Doe',
        creditLimit: const Value(10000),
        createdAt: DateTime.now(),
      ),
    )).id;

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(100),
        createdAt: DateTime.now(),
      ),
    )).id;

    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  // completeSale/recordPayment stamp createdAt with DateTime.now() and
  // don't expose it as a parameter — backdating afterwards gives the test
  // deterministic, well-separated dates instead of racing the real clock.
  // The ledger reads credit_transactions, so a sale's own createdAt no
  // longer places it on the statement — the CHARGE row written alongside it
  // does. Both are moved together to keep the two consistent.
  Future<void> setSaleCreatedAt(int saleId, DateTime date) async {
    await (db.update(
      db.sales,
    )..where((t) => t.id.equals(saleId))).write(SalesCompanion(createdAt: Value(date)));
    await (db.update(
      db.creditTransactions,
    )..where((t) => t.saleId.equals(saleId))).write(
      CreditTransactionsCompanion(createdAt: Value(date)),
    );
  }

  Future<void> setPaymentCreatedAt(int transactionId, DateTime date) {
    return (db.update(db.creditTransactions)..where((t) => t.id.equals(transactionId))).write(
      CreditTransactionsCompanion(createdAt: Value(date)),
    );
  }

  test(
    'returns every credit sale and payment sorted by date, with a running balance that '
    'reconciles against Customers.currentBalance two ways',
    () async {
      final day1 = DateTime(2026, 1, 1);
      final day2 = DateTime(2026, 1, 2);
      final day3 = DateTime(2026, 1, 3);
      final day4 = DateTime(2026, 1, 4);

      // A sale explicitly labeled 'credit'.
      final sale1 = await saleRepo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 100, quantity: 5)], // 500
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 0,
      );
      await setSaleCreatedAt(sale1.id, day1);

      final payment1 = await creditRepo.recordPayment(
        customerId: customerId,
        amount: 150,
        method: 'cash',
      );
      await setPaymentCreatedAt(payment1.id, day2);

      // A 'cash' sale that's still left with a balance due — counts as a
      // credit sale here too, same convention SaleRepository.completeSale
      // uses for the credit-limit check.
      final sale2 = await saleRepo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 100, quantity: 3)], // 300
        customerId: customerId,
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 100, // balance due: 200
      );
      await setSaleCreatedAt(sale2.id, day3);

      final payment2 = await creditRepo.recordPayment(
        customerId: customerId,
        amount: 100,
        method: 'mpesa',
      );
      await setPaymentCreatedAt(payment2.id, day4);

      final entries = await ledgerRepo.getLedgerForCustomer(customerId);

      expect(entries, hasLength(4));
      expect(entries.map((e) => e.date), [day1, day2, day3, day4]);
      expect(entries.map((e) => e.type), [
        CustomerLedgerEntryType.creditSale,
        CustomerLedgerEntryType.payment,
        CustomerLedgerEntryType.creditSale,
        CustomerLedgerEntryType.payment,
      ]);
      expect(entries.map((e) => e.reference), [
        sale1.invoiceNumber,
        'cash',
        sale2.invoiceNumber,
        'mpesa',
      ]);
      expect(entries.map((e) => e.amount), [500, 150, 200, 100]);
      expect(entries.map((e) => e.runningBalance), [500, 350, 550, 450]);

      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();

      // Reconciliation, way 1: the ledger's own running-balance column.
      expect(entries.last.runningBalance, customer.currentBalance);

      // Reconciliation, way 2: sum credit sales and payments independently,
      // with no reference to the running-balance column at all.
      final totalCreditSales = entries
          .where((e) => e.type == CustomerLedgerEntryType.creditSale)
          .fold<double>(0, (sum, e) => sum + e.amount);
      final totalPayments = entries
          .where((e) => e.type == CustomerLedgerEntryType.payment)
          .fold<double>(0, (sum, e) => sum + e.amount);
      expect(totalCreditSales - totalPayments, customer.currentBalance);
    },
  );

  test('a sale paid in full does not appear in the ledger', () async {
    await saleRepo.completeSale(
      cart: [CartLine(productId: productId, name: 'Soda', price: 100, quantity: 1)],
      customerId: customerId,
      userId: userId,
      paymentMethod: 'cash',
      amountPaid: 100, // total == amountPaid: no balance due
    );

    expect(await ledgerRepo.getLedgerForCustomer(customerId), isEmpty);
  });

  test('a customer with no activity gets an empty ledger', () async {
    expect(await ledgerRepo.getLedgerForCustomer(customerId), isEmpty);
  });

  test(
    'a voided credit sale leaves the ledger and the stored balance still reconciled',
    () async {
      final kept = await saleRepo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 100, quantity: 4)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 100, // 300 left owing
      );
      final voided = await saleRepo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', price: 100, quantity: 2)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 0, // 200 left owing, then reversed below
      );

      await saleRepo.voidSale(voided.uuid);

      final entries = await ledgerRepo.getLedgerForCustomer(customerId);
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();

      // The void is shown, not hidden: the charge stays on the statement
      // and a reversal cancels it, so the customer can see what happened
      // rather than finding a sale silently missing.
      expect(entries.map((e) => e.type), [
        CustomerLedgerEntryType.creditSale,
        CustomerLedgerEntryType.creditSale,
        CustomerLedgerEntryType.reversal,
      ]);
      expect(entries.map((e) => e.reference), [
        kept.invoiceNumber,
        voided.invoiceNumber,
        voided.invoiceNumber,
      ]);
      // The identity that matters: the ledger's own running total and the
      // customer's stored balance still agree after a void.
      expect(entries.last.runningBalance, 300);
      expect(customer.currentBalance, 300);
    },
  );
}
