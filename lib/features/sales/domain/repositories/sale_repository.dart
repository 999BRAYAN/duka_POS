import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';

/// Contract for creating and reading sales together with their line items.
abstract interface class SaleRepository {
  /// Creates a sale header and its line items in a single transaction, and
  /// is expected to decrement product stock (recording matching
  /// [StockMovement] rows) as part of that transaction.
  ///
  /// Before writing anything, checks every line's effective per-unit price
  /// — after its own item-level discount and its proportional share of the
  /// cart-level [discount] — against that product's minSellingPrice, and
  /// throws PriceBelowFloorException naming the first line that falls
  /// short. This lives here rather than only in a checkout screen so it
  /// can't be bypassed by a caller that skips UI validation.
  Future<Sale> createSale({
    required String invoiceNumber,
    int? customerId,
    required int userId,
    required List<SaleItemsCompanion> items,
    double discount,
    double tax,
    required String paymentMethod,
    double amountPaid,
  });

  /// The cart-checkout path: builds a sale straight from a [CartLine] list
  /// in one transaction, re-checking everything at this moment rather than
  /// trusting anything the cart captured when lines were added —
  /// - current stock per line (another sale could have taken the last unit
  ///   since the cart was built; throws InsufficientStockException),
  /// - the same minSellingPrice floor check as [createSale], applied to the
  ///   cart's lines with [discount] allocated proportionally (throws
  ///   PriceBelowFloorException),
  /// - and, whenever the sale would leave a balance due (total minus
  ///   [amountPaid], for any payment method — not just 'credit'), that the
  ///   resulting balance doesn't exceed the customer's creditLimit (throws
  ///   CreditLimitExceededException) unless [overrideCreditLimit] is set.
  ///   This repository doesn't check who's allowed to pass that flag —
  ///   SaleService.completeSale requires Permission.overrideCreditLimit
  ///   before forwarding it here, same split as the [Permission.processSale]
  ///   check on the rest of this method.
  ///
  /// Each line's cost is snapshotted from the product's current costPrice
  /// at this moment (not any earlier value) when recording its
  /// StockMovementRepository.recordMovement call, and those snapshots are
  /// summed into the returned Sale's cogs/grossProfit. The sale's
  /// invoiceNumber is generated inside this same transaction as a gapless
  /// sequence (a count of every sale ever created, void or not), so two
  /// near-simultaneous calls can't collide or skip a number.
  ///
  /// paymentMethod 'credit' with no [customerId] throws
  /// CustomerRequiredForCreditException. If there's a customer and a
  /// balance due (total minus [amountPaid], for any payment method), that
  /// shortfall is added to Customers.balance.
  Future<Sale> completeSale({
    required List<CartLine> cart,
    int? customerId,
    required int userId,
    required String paymentMethod,
    double amountPaid,
    double discount,
    bool overrideCreditLimit,
  });

  /// Reverses a completed sale: the goods return to stock and any unpaid
  /// balance comes off the customer, in one transaction. [reason] and
  /// [voidedByUserId] are recorded on the sale — a void moves both stock
  /// and money, so who did it and why is the only record of what happened.
  Future<void> voidSale(String uuid, {String? reason, int? voidedByUserId});

  Future<Sale?> getSaleByUuid(String uuid);

  Future<List<SaleItem>> getItemsForSale(int saleId);

  Stream<List<Sale>> watchSales();

  Stream<List<Sale>> watchSalesForDateRange(DateTime start, DateTime end);

  /// Records a payment against [customerId]'s outstanding balance — same
  /// effect as CreditRepository.recordPayment (which this calls) — and
  /// additionally allocates it across that customer's outstanding
  /// (non-void) sales, oldest first, increasing each affected sale's
  /// amountPaid until the payment is exhausted or every outstanding sale is
  /// covered. Sales.amountPaid otherwise has exactly one writer
  /// ([completeSale]); this is the second, deliberately kept here rather
  /// than in CreditRepository so that stays true — mirrors
  /// PurchaseRepository.recordPayment updating its one specific purchase's
  /// amountPaid, just spread across possibly-many sales since a credit
  /// payment isn't tied to one sale the way a purchase payment is tied to
  /// one purchase. This is what makes SalesHistoryScreen's "Paid"/"On
  /// account" status (a pure read of amountPaid vs total) catch up once a
  /// credit sale is paid off, instead of staying frozen at "On account".
  Future<CreditTransaction> recordCustomerPayment({
    required int customerId,
    required double amount,
    required String method,
    String? notes,
  });
}
