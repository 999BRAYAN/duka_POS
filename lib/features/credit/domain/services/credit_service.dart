import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/domain/repositories/credit_repository.dart';

/// Application-layer entry point for taking a customer's debt payment:
/// enforces [Permission.manageCustomers] in front of
/// [CreditRepository.recordPayment], which stays a plain data-access
/// boundary (mirrors ProductService/CustomerService's split from their
/// repositories). A cashier taking a payment at the till is a defensible
/// product decision later, but for now credit collection is a
/// manager/admin action, same table as managing customers themselves.
class CreditService {
  CreditService(this._repository, this._authorizationService);

  final CreditRepository _repository;
  final AuthorizationService _authorizationService;

  Future<CreditTransaction> recordPayment({
    required int customerId,
    required double amount,
    required String method,
    String? notes,
  }) {
    _authorizationService.require(Permission.manageCustomers);
    return _repository.recordPayment(
      customerId: customerId,
      amount: amount,
      method: method,
      notes: notes,
    );
  }
}
