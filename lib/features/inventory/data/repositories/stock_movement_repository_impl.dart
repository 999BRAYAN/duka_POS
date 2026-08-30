import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:uuid/uuid.dart';

class StockMovementRepositoryImpl implements StockMovementRepository {
  StockMovementRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<StockMovement> recordMovement({
    required int productId,
    required String type,
    required double quantity,
    String? reference,
    String? notes,
    int? userId,
  }) {
    return _db.into(_db.stockMovements).insertReturning(
      StockMovementsCompanion.insert(
        uuid: _uuid.v4(),
        productId: productId,
        type: type,
        quantity: quantity,
        reference: Value(reference),
        notes: Value(notes),
        userId: Value(userId),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Stream<List<StockMovement>> watchMovementsForProduct(int productId) {
    return (_db.select(_db.stockMovements)
          ..where((t) => t.productId.equals(productId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  @override
  Stream<List<StockMovement>> watchRecentMovements({int limit = 50}) {
    return (_db.select(_db.stockMovements)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .watch();
  }
}
