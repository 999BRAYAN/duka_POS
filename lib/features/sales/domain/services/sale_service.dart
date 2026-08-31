import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';

/// Application-layer entry point for checkout: enforces
/// [Permission.processSale] in front of [SaleRepository.completeSale],
/// which stays a plain data-access boundary (mirrors ProductService /
/// InventoryService / PurchaseService's split from their repositories).
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
}
