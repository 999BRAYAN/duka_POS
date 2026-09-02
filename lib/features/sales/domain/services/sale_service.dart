import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';

/// Application-layer entry point for checkout: enforces
/// [Permission.processSale] in front of [SaleRepository.completeSale],
/// which stays a plain data-access boundary (mirrors ProductService /
/// InventoryService / PurchaseService's split from their repositories).
///
/// Bypassing the repository's credit-limit check additionally requires
/// [Permission.overrideCreditLimit] — a cashier can ring up sales but can't
/// grant credit beyond what a customer already qualifies for; that call is
/// reserved for whoever holds this permission (admin/manager today).
class SaleService {
  SaleService(this._repository, this._authorizationService);

  final SaleRepository _repository;
  final AuthorizationService _authorizationService;

  Future<Sale> completeSale({
    required List<CartLine> cart,
    int? customerId,
    required int userId,
    required String paymentMethod,
    double amountPaid = 0,
    double discount = 0,
    bool overrideCreditLimit = false,
  }) {
    _authorizationService.require(Permission.processSale);
    if (overrideCreditLimit) {
      _authorizationService.require(Permission.overrideCreditLimit);
    }
    return _repository.completeSale(
      cart: cart,
      customerId: customerId,
      userId: userId,
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      discount: discount,
      overrideCreditLimit: overrideCreditLimit,
    );
  }

  /// Voids a completed sale. Requires [Permission.voidSale] and a non-blank
  /// [reason] — a cashier who could void their own sales could take cash out
  /// of the till and erase the record of it, and a void with no reason
  /// leaves nothing to reconcile against.
  Future<void> voidSale({
    required String uuid,
    required String reason,
    int? voidedByUserId,
  }) {
    _authorizationService.require(Permission.voidSale);
    if (reason.trim().isEmpty) throw const MissingVoidReasonException();
    return _repository.voidSale(
      uuid,
      reason: reason.trim(),
      voidedByUserId: voidedByUserId,
    );
  }
}
