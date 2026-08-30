import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/domain/repositories/credit_repository.dart';
import 'package:uuid/uuid.dart';

class CreditRepositoryImpl implements CreditRepository {
  CreditRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<CreditTransaction> chargeCustomer({
    required int customerId,
    int? saleId,
    required double amount,
    String? notes,
  }) {
    return _applyTransaction(
      customerId: customerId,
      saleId: saleId,
      type: 'CHARGE',
      amount: amount,
      balanceDelta: amount,
      notes: notes,
    );
  }

  @override
  Future<CreditTransaction> recordPayment({
    required int customerId,
    required double amount,
    String? notes,
  }) {
    return _applyTransaction(
      customerId: customerId,
      saleId: null,
      type: 'PAYMENT',
      amount: amount,
      balanceDelta: -amount,
      notes: notes,
    );
  }

  Future<CreditTransaction> _applyTransaction({
    required int customerId,
    required int? saleId,
    required String type,
    required double amount,
    required double balanceDelta,
    required String? notes,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final customer = await (_db.select(
        _db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();
      final balanceAfter = customer.currentBalance + balanceDelta;

      final transaction = await _db.into(_db.creditTransactions).insertReturning(
        CreditTransactionsCompanion.insert(
          uuid: _uuid.v4(),
          customerId: customerId,
          saleId: Value(saleId),
          type: type,
          amount: amount,
          balanceAfter: balanceAfter,
          notes: Value(notes),
          createdAt: now,
        ),
      );

      await (_db.update(
        _db.customers,
      )..where((t) => t.id.equals(customerId))).write(
        CustomersCompanion(
          currentBalance: Value(balanceAfter),
          updatedAt: Value(now),
        ),
      );

      return transaction;
    });
  }

  @override
  Stream<List<CreditTransaction>> watchTransactionsForCustomer(
    int customerId,
  ) {
    return (_db.select(_db.creditTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  @override
  Future<double> getCustomerBalance(int customerId) async {
    final customer = await (_db.select(
      _db.customers,
    )..where((t) => t.id.equals(customerId))).getSingle();
    return customer.currentBalance;
  }
}
