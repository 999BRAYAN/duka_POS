import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Expense] rows.
abstract interface class ExpenseRepository {
  Future<Expense> addExpense({
    required String category,
    required String description,
    required double amount,
    int? userId,
  });

  Future<void> deleteExpense(String uuid);

  Stream<List<Expense>> watchExpenses();

  Stream<List<Expense>> watchExpensesForDateRange(DateTime start, DateTime end);
}
