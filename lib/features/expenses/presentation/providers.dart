import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/expenses/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final expensesStreamProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchExpenses();
});
