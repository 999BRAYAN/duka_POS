import 'package:duka_pos/core/database/database.dart';

/// Contract for creating and reading purchase orders together with their
/// line items.
abstract interface class PurchaseRepository {
  Future<Purchase> createPurchase({
    String? referenceNumber,
    required int supplierId,
    required int userId,
    required List<PurchaseItemsCompanion> items,
    double discount,
    double tax,
  });

  /// Marks a purchase as received and is expected to increment product
  /// stock (recording matching [StockMovement] rows) as part of that
  /// transaction.
  Future<void> markPurchaseReceived(String uuid);

  Future<void> cancelPurchase(String uuid);

  /// Records stock received from a supplier in one transaction, already
  /// marked 'received' — for shops that log a purchase at the moment goods
  /// arrive rather than creating a pending order first. For each item:
  /// reads the product's current stock and costPrice, computes the new
  /// quantity-weighted average cost, records the stock change via
  /// [StockMovementRepository.recordMovement] (the only path allowed to
  /// touch [Product.stock] — this does not update stock any other way),
  /// and writes that average back to [Product.costPrice]. Then inserts the
  /// Purchase and PurchaseItems rows, and — if [amountPaid] is less than
  /// the computed total — adds the shortfall to the supplier's
  /// [Supplier.balance].
  ///
  /// Throws [InvalidPaymentStatusException] if [paymentStatus] isn't one of
  /// 'paid', 'partial' or 'unpaid'.
  Future<Purchase> receiveStock({
    String? referenceNumber,
    required int supplierId,
    required int userId,
    required List<PurchaseItemsCompanion> items,
    double discount,
    double tax,
    required String paymentStatus,
    required double amountPaid,
  });

  /// Records a payment against a purchase already marked 'received',
  /// increasing [Purchase.amountPaid] and moving [Purchase.paymentStatus] to
  /// 'partial' or 'paid' accordingly, while reducing the supplier's
  /// [Supplier.balance] by the same amount (floored at zero). The only way a
  /// purchase's payment status can change after it was received — there was
  /// previously no path from 'unpaid'/'partial' to 'paid' once stock had
  /// come in.
  ///
  /// Throws [InvalidPurchaseStatusException] if the purchase isn't
  /// 'received', or [InvalidPurchasePaymentException] if [amount] isn't
  /// positive or exceeds what's still owed (total minus amountPaid).
  Future<Purchase> recordPayment(String uuid, {required double amount});

  Future<Purchase?> getPurchaseByUuid(String uuid);

  Future<List<PurchaseItem>> getItemsForPurchase(int purchaseId);

  Stream<List<Purchase>> watchPurchases();
}
