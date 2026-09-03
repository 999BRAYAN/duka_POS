import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';

/// Application-layer entry point for taking a customer's debt payment:
/// enforces [Permission.manageCustomers] in front of
/// SaleRepository.recordCustomerPayment, which stays a plain data-access
/// boundary (mirrors ProductService/CustomerService's split from their
/// repositories). A cashier taking a payment at the till is a defensible
/// product decision later, but for now credit collection is a
/// manager/admin action, same table as managing customers themselves.
///
/// Depends on [SaleRepository] rather than CreditRepository directly:
/// SaleRepository already depends on CreditRepository (to charge/reverse a
/// sale's credit), so going the other way here — CreditRepository is never
/// allowed to depend on SaleRepository — is what keeps this a DAG instead
/// of a cycle, and is what lets recordCustomerPayment also update the
/// affected sales' amountPaid, not just the customer's balance.
class CreditService {
  CreditService(this._saleRepository, this._authorizationService);

  final SaleRepository _saleRepository;
  final AuthorizationService _authorizationService;

  Future<CreditTransaction> recordPayment({
    required int customerId,
    required double amount,
    required String method,
    String? notes,
  }) {
    _authorizationService.require(Permission.manageCustomers);
    return _saleRepository.recordCustomerPayment(
      customerId: customerId,
      amount: amount,
      method: method,
      notes: notes,
    );
  }
}
