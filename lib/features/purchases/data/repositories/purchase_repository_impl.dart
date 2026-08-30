import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/purchases/domain/exceptions.dart';
import 'package:duka_pos/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:uuid/uuid.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  PurchaseRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Purchase> createPurchase({
    String? referenceNumber,
    required int supplierId,
    required int userId,
    required List<PurchaseItemsCompanion> items,
    double discount = 0,
    double tax = 0,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.total.value);

      final purchase = await _db.into(_db.purchases).insertReturning(
        PurchasesCompanion.insert(
          uuid: _uuid.v4(),
          referenceNumber: Value(referenceNumber),
          supplierId: supplierId,
          userId: userId,
          subtotal: Value(subtotal),
          discount: Value(discount),
          tax: Value(tax),
          total: Value(subtotal - discount + tax),
          createdAt: now,
        ),
      );

      for (final item in items) {
        await _db.into(_db.purchaseItems).insert(
          item.copyWith(
            uuid: Value(_uuid.v4()),
            purchaseId: Value(purchase.id),
            createdAt: Value(now),
          ),
        );
      }

      return purchase;
    });
  }

  @override
  Future<void> markPurchaseReceived(String uuid) {
    return _db.transaction(() async {
      final purchase = await (_db.select(
        _db.purchases,
      )..where((t) => t.uuid.equals(uuid))).getSingle();

      if (purchase.status != 'pending') {
        throw InvalidPurchaseStatusException(
          'Cannot mark purchase as received: current status is '
          "'${purchase.status}', expected 'pending'.",
        );
      }

      final now = DateTime.now();
      final items = await (_db.select(
        _db.purchaseItems,
      )..where((t) => t.purchaseId.equals(purchase.id))).get();

      for (final item in items) {
        final product = await (_db.select(
          _db.products,
        )..where((t) => t.id.equals(item.productId))).getSingle();
        await (_db.update(
          _db.products,
        )..where((t) => t.id.equals(item.productId))).write(
          ProductsCompanion(
            stock: Value(product.stock + item.quantity),
            updatedAt: Value(now),
          ),
        );

        await _db.into(_db.stockMovements).insert(
          StockMovementsCompanion.insert(
            uuid: _uuid.v4(),
            productId: item.productId,
            type: 'PURCHASE',
            quantity: item.quantity,
            reference: Value(purchase.uuid),
            createdAt: now,
          ),
        );
      }

      await (_db.update(
        _db.purchases,
      )..where((t) => t.uuid.equals(uuid))).write(
        PurchasesCompanion(
          status: const Value('received'),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> cancelPurchase(String uuid) async {
    final purchase = await (_db.select(
      _db.purchases,
    )..where((t) => t.uuid.equals(uuid))).getSingle();

    if (purchase.status == 'received') {
      throw const InvalidPurchaseStatusException(
        'Cannot cancel a purchase that has already been received.',
      );
    }

    await (_db.update(
      _db.purchases,
    )..where((t) => t.uuid.equals(uuid))).write(
      PurchasesCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<Purchase?> getPurchaseByUuid(String uuid) {
    return (_db.select(
      _db.purchases,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Future<List<PurchaseItem>> getItemsForPurchase(int purchaseId) {
    return (_db.select(
      _db.purchaseItems,
    )..where((t) => t.purchaseId.equals(purchaseId))).get();
  }

  @override
  Stream<List<Purchase>> watchPurchases() {
    return (_db.select(_db.purchases)..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ])).watch();
  }
}
