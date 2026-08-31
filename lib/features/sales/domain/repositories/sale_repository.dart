import 'package:duka_pos/core/database/database.dart';

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

  Future<void> voidSale(String uuid);

  Future<Sale?> getSaleByUuid(String uuid);

  Future<List<SaleItem>> getItemsForSale(int saleId);

  Stream<List<Sale>> watchSales();

  Stream<List<Sale>> watchSalesForDateRange(DateTime start, DateTime end);
}
