import 'package:duka_pos/core/database/database.dart';

/// Contract for recording and reading [StockMovement] rows — the audit
/// trail behind every change to a product's stock level.
abstract interface class StockMovementRepository {
  Future<StockMovement> recordMovement({
    required int productId,
    required String type,
    required double quantity,
    String? reference,
    String? notes,
    int? userId,
  });

  Stream<List<StockMovement>> watchMovementsForProduct(int productId);

  Stream<List<StockMovement>> watchRecentMovements({int limit});
}
