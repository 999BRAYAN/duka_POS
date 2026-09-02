import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/purchases/domain/repositories/purchase_repository.dart';

/// Application-layer entry point for receiving stock: enforces
/// [Permission.receiveStock] in front of
/// [PurchaseRepository.receiveStock], which stays a plain data-access
/// boundary (mirrors ProductService/InventoryService's split from their
/// repositories).
class PurchaseService {
  PurchaseService(this._repository, this._authorizationService);

  final PurchaseRepository _repository;
  final AuthorizationService _authorizationService;

  Future<Purchase> receiveStock({
    String? referenceNumber,
    required int supplierId,
    required int userId,
    required List<PurchaseItemsCompanion> items,
    double discount = 0,
    double tax = 0,
    required String paymentStatus,
    required double amountPaid,
  }) {
    _authorizationService.require(Permission.receiveStock);
    return _repository.receiveStock(
      referenceNumber: referenceNumber,
      supplierId: supplierId,
      userId: userId,
      items: items,
      discount: discount,
      tax: tax,
      paymentStatus: paymentStatus,
      amountPaid: amountPaid,
    );
  }

  /// Same permission as receiving stock — recording a payment against an
  /// already-received purchase is a sibling action, not a separate
  /// capability.
  Future<Purchase> recordPayment(String uuid, {required double amount}) {
    _authorizationService.require(Permission.receiveStock);
    return _repository.recordPayment(uuid, amount: amount);
  }
}
