import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:duka_pos/features/expenses/domain/repositories/expense_repository.dart';
import 'package:duka_pos/features/expenses/domain/services/expense_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  return ExpenseRepositoryImpl(ref.watch(databaseProvider));
});

final expenseServiceProvider = Provider<ExpenseService>((ref) {
  return ExpenseService(
    ref.watch(expenseRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
