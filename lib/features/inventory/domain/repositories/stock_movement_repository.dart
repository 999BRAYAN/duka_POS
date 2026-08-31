import 'package:duka_pos/core/database/database.dart';

/// Contract for recording [StockMovement] rows — the *only* sanctioned path
/// for changing [Product.stock]. [recordMovement] updates both in one
/// transaction, so every stock change carries a matching audit-trail row.
/// No other code should write to `products.stock` directly; route sale,
/// purchase, return and manual-adjustment stock changes through here (manual
/// adjustments go through InventoryService.adjustStock instead, which adds
/// the Permission.adjustStock gate and a required reason).
abstract interface class StockMovementRepository {
  Future<StockMovement> recordMovement({
    required int productId,
    required String type,
    required double quantity,
    double? unitCost,
    String? reference,
    String? notes,
    int? userId,
  });

  Stream<List<StockMovement>> watchMovementsForProduct(int productId);

  Stream<List<StockMovement>> watchRecentMovements({int limit});
}
