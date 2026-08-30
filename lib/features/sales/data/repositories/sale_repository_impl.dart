import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';
import 'package:uuid/uuid.dart';

/// Stock movement quantities are stored as the signed delta applied to the
/// product's stock: negative for a sale (stock leaving), positive for a
/// void/return (stock coming back).
class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Sale> createSale({
    required String invoiceNumber,
    int? customerId,
    required int userId,
    required List<SaleItemsCompanion> items,
    double discount = 0,
    double tax = 0,
    required String paymentMethod,
    double amountPaid = 0,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final subtotal = items.fold<double>(0, (sum, i) => sum + i.total.value);

      final sale = await _db.into(_db.sales).insertReturning(
        SalesCompanion.insert(
          uuid: _uuid.v4(),
          invoiceNumber: invoiceNumber,
          customerId: Value(customerId),
          userId: userId,
          subtotal: Value(subtotal),
          discount: Value(discount),
          tax: Value(tax),
          total: Value(subtotal - discount + tax),
          amountPaid: Value(amountPaid),
          paymentMethod: paymentMethod,
          createdAt: now,
        ),
      );

      for (final item in items) {
        await _db.into(_db.saleItems).insert(
          item.copyWith(
            uuid: Value(_uuid.v4()),
            saleId: Value(sale.id),
            createdAt: Value(now),
          ),
        );

        final productId = item.productId.value;
        final quantity = item.quantity.value;

        final product = await (_db.select(
          _db.products,
        )..where((t) => t.id.equals(productId))).getSingle();
        await (_db.update(
          _db.products,
        )..where((t) => t.id.equals(productId))).write(
          ProductsCompanion(
            stock: Value(product.stock - quantity),
            updatedAt: Value(now),
          ),
        );

        await _db.into(_db.stockMovements).insert(
          StockMovementsCompanion.insert(
            uuid: _uuid.v4(),
            productId: productId,
            type: 'SALE',
            quantity: -quantity,
            reference: Value(sale.uuid),
            userId: Value(userId),
            createdAt: now,
          ),
        );
      }

      return sale;
    });
  }

  @override
  Future<void> voidSale(String uuid) {
    return _db.transaction(() async {
      final sale = await (_db.select(
        _db.sales,
      )..where((t) => t.uuid.equals(uuid))).getSingle();
      final now = DateTime.now();

      final items = await (_db.select(
        _db.saleItems,
      )..where((t) => t.saleId.equals(sale.id))).get();

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
            type: 'RETURN',
            quantity: item.quantity,
            reference: Value(sale.uuid),
            createdAt: now,
          ),
        );
      }

      await (_db.update(_db.sales)..where((t) => t.uuid.equals(uuid))).write(
        SalesCompanion(status: const Value('void'), updatedAt: Value(now)),
      );
    });
  }

  @override
  Future<Sale?> getSaleByUuid(String uuid) {
    return (_db.select(
      _db.sales,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Future<List<SaleItem>> getItemsForSale(int saleId) {
    return (_db.select(
      _db.saleItems,
    )..where((t) => t.saleId.equals(saleId))).get();
  }

  @override
  Stream<List<Sale>> watchSales() {
    return (_db.select(_db.sales)..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ])).watch();
  }

  @override
  Stream<List<Sale>> watchSalesForDateRange(DateTime start, DateTime end) {
    return (_db.select(_db.sales)
          ..where((t) => t.createdAt.isBetweenValues(start, end))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }
}
