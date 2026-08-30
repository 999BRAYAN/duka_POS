import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/expenses/domain/repositories/expense_repository.dart';
import 'package:uuid/uuid.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Expense> addExpense({
    required String category,
    required String description,
    required double amount,
    int? userId,
  }) {
    return _db.into(_db.expenses).insertReturning(
      ExpensesCompanion.insert(
        uuid: _uuid.v4(),
        category: category,
        description: description,
        amount: amount,
        userId: Value(userId),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteExpense(String uuid) {
    return (_db.delete(
      _db.expenses,
    )..where((t) => t.uuid.equals(uuid))).go();
  }

  @override
  Stream<List<Expense>> watchExpenses() {
    return (_db.select(_db.expenses)..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ])).watch();
  }

  @override
  Stream<List<Expense>> watchExpensesForDateRange(DateTime start, DateTime end) {
    return (_db.select(_db.expenses)
          ..where((t) => t.createdAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }
}
