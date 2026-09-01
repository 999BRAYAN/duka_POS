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

  Future<void> voidSale(String uuid);

  Future<Sale?> getSaleByUuid(String uuid);

  Future<List<SaleItem>> getItemsForSale(int saleId);

  Stream<List<Sale>> watchSales();

  Stream<List<Sale>> watchSalesForDateRange(DateTime start, DateTime end);
}
