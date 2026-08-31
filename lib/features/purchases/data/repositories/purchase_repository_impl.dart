import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:duka_pos/features/purchases/domain/exceptions.dart';
import 'package:duka_pos/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:uuid/uuid.dart';

/// Actual stock changes go through [StockMovementRepository.recordMovement]
/// rather than writing `products.stock` here — see that repository's class
/// doc.
class PurchaseRepositoryImpl implements PurchaseRepository {
  PurchaseRepositoryImpl(this._db, this._stockMovements);

  final DukaDatabase _db;
  final StockMovementRepository _stockMovements;
  static const _uuid = Uuid();
  static const _validPaymentStatuses = {'paid', 'partial', 'unpaid'};

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
        await _stockMovements.recordMovement(
          productId: item.productId,
          type: 'PURCHASE',
          quantity: item.quantity,
          unitCost: item.unitCost,
          reference: purchase.uuid,
          userId: purchase.userId,
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
  Future<Purchase> receiveStock({
    String? referenceNumber,
    required int supplierId,
    required int userId,
    required List<PurchaseItemsCompanion> items,
    double discount = 0,
    double tax = 0,
    required String paymentStatus,
    required double amountPaid,
  }) async {
    if (!_validPaymentStatuses.contains(paymentStatus)) {
      throw InvalidPaymentStatusException(
        "Unknown payment status '$paymentStatus'; expected one of "
        '$_validPaymentStatuses.',
      );
    }

    return _db.transaction(() async {
      final now = DateTime.now();
      // Generated up front so recordMovement (called per item, before the
      // Purchase row exists) can still reference it.
      final purchaseUuid = _uuid.v4();
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.total.value);
      final total = subtotal - discount + tax;

      for (final item in items) {
        final productId = item.productId.value;
        final quantity = item.quantity.value;
        final unitCost = item.unitCost.value;

        final product = await (_db.select(
          _db.products,
        )..where((t) => t.id.equals(productId))).getSingle();

        final newCost =
            (product.stock * product.costPrice + quantity * unitCost) /
            (product.stock + quantity);

        await _stockMovements.recordMovement(
          productId: productId,
          type: 'PURCHASE',
          quantity: quantity,
          unitCost: unitCost,
          reference: purchaseUuid,
          userId: userId,
        );

        await (_db.update(
          _db.products,
        )..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(costPrice: Value(newCost), updatedAt: Value(now)),
        );
      }

      final purchase = await _db.into(_db.purchases).insertReturning(
        PurchasesCompanion.insert(
          uuid: purchaseUuid,
          referenceNumber: Value(referenceNumber),
          supplierId: supplierId,
          userId: userId,
          subtotal: Value(subtotal),
          discount: Value(discount),
          tax: Value(tax),
          total: Value(total),
          amountPaid: Value(amountPaid),
          status: const Value('received'),
          paymentStatus: Value(paymentStatus),
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

      final outstanding = total - amountPaid;
      if (outstanding > 0) {
        final supplier = await (_db.select(
          _db.suppliers,
        )..where((t) => t.id.equals(supplierId))).getSingle();

        await (_db.update(
          _db.suppliers,
        )..where((t) => t.id.equals(supplierId))).write(
          SuppliersCompanion(
            balance: Value(supplier.balance + outstanding),
            updatedAt: Value(now),
          ),
        );
      }

      return purchase;
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
