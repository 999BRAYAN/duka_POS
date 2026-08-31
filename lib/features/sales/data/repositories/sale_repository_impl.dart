import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';
import 'package:uuid/uuid.dart';

/// Stock movement quantities are stored as the signed delta applied to the
/// product's stock: negative for a sale (stock leaving), positive for a
/// void/return (stock coming back). Actual stock changes go through
/// [StockMovementRepository.recordMovement] rather than writing
/// `products.stock` here — see that repository's class doc.
class SaleRepositoryImpl implements SaleRepository {
  SaleRepositoryImpl(this._db, this._stockMovements);

  final DukaDatabase _db;
  final StockMovementRepository _stockMovements;
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

      // Fetched once up front: reused both for the floor check below and
      // for costPrice when recording each stock movement, and means the
      // floor check runs (and can throw, rolling back the transaction)
      // before anything is written.
      final products = <int, Product>{};
      for (final item in items) {
        final productId = item.productId.value;
        products[productId] ??= await (_db.select(
          _db.products,
        )..where((t) => t.id.equals(productId))).getSingle();
      }

      _assertNoLineBelowFloor(items: items, subtotal: subtotal, cartDiscount: discount, products: products);

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
        final product = products[productId]!;

        await _stockMovements.recordMovement(
          productId: productId,
          type: 'SALE',
          quantity: -quantity,
          unitCost: product.costPrice,
          reference: sale.uuid,
          userId: userId,
        );
      }

      return sale;
    });
  }

  /// [item.total] is taken as already net of that line's own item-level
  /// discount (the convention the rest of this method's `subtotal` uses),
  /// so the only further deduction applied here is [cartDiscount],
  /// allocated across lines in proportion to their share of [subtotal].
  void _assertNoLineBelowFloor({
    required List<SaleItemsCompanion> items,
    required double subtotal,
    required double cartDiscount,
    required Map<int, Product> products,
  }) {
    for (final item in items) {
      final quantity = item.quantity.value;
      if (quantity <= 0) continue;

      final lineTotal = item.total.value;
      final allocatedCartDiscount = subtotal > 0
          ? cartDiscount * (lineTotal / subtotal)
          : 0.0;
      final effectivePrice = (lineTotal - allocatedCartDiscount) / quantity;

      final product = products[item.productId.value]!;
      if (effectivePrice < product.minSellingPrice) {
        throw PriceBelowFloorException(
          productName: product.name,
          effectivePrice: effectivePrice,
          minSellingPrice: product.minSellingPrice,
        );
      }
    }
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

        await _stockMovements.recordMovement(
          productId: item.productId,
          type: 'RETURN',
          quantity: item.quantity,
          unitCost: product.costPrice,
          reference: sale.uuid,
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
