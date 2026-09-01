import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/expenses/domain/repositories/expense_repository.dart';

/// Application-layer entry point for recording an expense: enforces
/// [Permission.manageExpenses] in front of [ExpenseRepository.addExpense],
/// which stays a plain data-access boundary (mirrors ProductService/
/// CustomerService's split from their repositories).
class ExpenseService {
  ExpenseService(this._repository, this._authorizationService);

  final ExpenseRepository _repository;
  final AuthorizationService _authorizationService;

  Future<Expense> addExpense({
    required String category,
    required String description,
    required double amount,
    int? userId,
  }) {
    _authorizationService.require(Permission.manageExpenses);
    return _repository.addExpense(
      category: category,
      description: description,
      amount: amount,
      userId: userId,
    );
  }
}
