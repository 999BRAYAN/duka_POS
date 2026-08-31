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
    double? unitCost,
    String? reference,
    String? notes,
    int? userId,
  }) {
    // Insert + stock update happen in one transaction so a product's stock
    // and its audit trail can never drift apart. Other repositories that
    // share this `_db` instance (Sale/Purchase) call this from inside their
    // own `_db.transaction()` — drift keeps a single transaction active per
    // zone regardless of which repository object issues the query, so this
    // still participates in their outer transaction rather than starting a
    // nested one.
    return _db.transaction(() async {
      final now = DateTime.now();
      final product = await (_db.select(
        _db.products,
      )..where((t) => t.id.equals(productId))).getSingle();

      await (_db.update(
        _db.products,
      )..where((t) => t.id.equals(productId))).write(
        ProductsCompanion(
          stock: Value(product.stock + quantity),
          updatedAt: Value(now),
        ),
      );

      return _db.into(_db.stockMovements).insertReturning(
        StockMovementsCompanion.insert(
          uuid: _uuid.v4(),
          productId: productId,
          type: type,
          quantity: quantity,
          unitCost: Value(unitCost),
          reference: Value(reference),
          notes: Value(notes),
          userId: Value(userId),
          createdAt: now,
        ),
      );
    });
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
