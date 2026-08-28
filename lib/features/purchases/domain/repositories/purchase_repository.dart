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

  Future<Purchase?> getPurchaseByUuid(String uuid);

  Future<List<PurchaseItem>> getItemsForPurchase(int purchaseId);

  Stream<List<Purchase>> watchPurchases();
}
