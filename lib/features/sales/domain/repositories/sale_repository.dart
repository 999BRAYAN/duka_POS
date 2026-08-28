import 'package:duka_pos/core/database/database.dart';

/// Contract for creating and reading sales together with their line items.
abstract interface class SaleRepository {
  /// Creates a sale header and its line items in a single transaction, and
  /// is expected to decrement product stock (recording matching
  /// [StockMovement] rows) as part of that transaction.
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
