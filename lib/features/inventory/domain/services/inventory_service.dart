import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/exceptions.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';

/// Application-layer entry point for stock changes that aren't driven by a
/// sale or purchase (stock counts, damage, theft, corrections). Sale/void
/// and purchase-received flows record their own SALE/RETURN/PURCHASE
/// movements directly via [StockMovementRepository.recordMovement] — they're
/// already gated by whatever permission guards making a sale or receiving a
/// purchase, so they don't go through here.
class InventoryService {
  InventoryService(this._stockMovements, this._authorizationService);

  final StockMovementRepository _stockMovements;
  final AuthorizationService _authorizationService;

  /// Records a manual stock correction. Requires [Permission.adjustStock]
  /// and a non-blank [reason]; both are enforced before anything is written.
  Future<StockMovement> adjustStock({
    required int productId,
    required double quantityChange,
    required String reason,
    int? userId,
  }) {
    _authorizationService.require(Permission.adjustStock);
    if (reason.trim().isEmpty) {
      throw const MissingAdjustmentReasonException();
    }
    return _stockMovements.recordMovement(
      productId: productId,
      type: 'ADJUSTMENT',
      quantity: quantityChange,
      notes: reason,
      userId: userId,
    );
  }
}
