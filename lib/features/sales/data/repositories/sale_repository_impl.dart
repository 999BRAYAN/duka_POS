import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';
import 'package:uuid/uuid.dart';

typedef _PriceLine = ({int productId, double quantity, double lineTotal});

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

      _assertNoLineBelowFloor(
        lines: [
          for (final item in items)
            (
              productId: item.productId.value,
              quantity: item.quantity.value,
              lineTotal: item.total.value,
            ),
        ],
        subtotal: subtotal,
        cartDiscount: discount,
        products: products,
      );

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

  @override
  Future<Sale> completeSale({
    required List<CartLine> cart,
    int? customerId,
    required int userId,
    required String paymentMethod,
    double amountPaid = 0,
    double discount = 0,
    bool overrideCreditLimit = false,
  }) async {
    if (cart.isEmpty) {
      throw ArgumentError.value(cart, 'cart', 'Cannot complete a sale with an empty cart.');
    }
    if (paymentMethod == 'credit' && customerId == null) {
      throw const CustomerRequiredForCreditException();
    }

    return _db.transaction(() async {
      final now = DateTime.now();
      final subtotal = cart.fold<double>(0, (sum, line) => sum + line.lineTotal);
      final total = subtotal - discount;

      // Fetched fresh, once, right here — never the cart's own snapshot —
      // since both stock and cost may have moved since a line was added.
      final products = <int, Product>{};
      for (final line in cart) {
        products[line.productId] ??= await (_db.select(
          _db.products,
        )..where((t) => t.id.equals(line.productId))).getSingle();
      }

      for (final line in cart) {
        final product = products[line.productId]!;
        if (product.stock < line.quantity) {
          throw InsufficientStockException(
            productName: product.name,
            requested: line.quantity,
            available: product.stock,
          );
        }
      }

      _assertNoLineBelowFloor(
        lines: [
          for (final line in cart)
            (productId: line.productId, quantity: line.quantity, lineTotal: line.lineTotal),
        ],
        subtotal: subtotal,
        cartDiscount: discount,
        products: products,
      );

      Customer? customer;
      if (customerId != null) {
        customer = await (_db.select(
          _db.customers,
        )..where((t) => t.id.equals(customerId))).getSingle();
      }

      final balanceDue = total - amountPaid;
      if (paymentMethod == 'credit' && !overrideCreditLimit) {
        final wouldBeBalance = customer!.currentBalance + balanceDue;
        if (wouldBeBalance > customer.creditLimit) {
          throw CreditLimitExceededException(
            customerName: customer.name,
            wouldBeBalance: wouldBeBalance,
            creditLimit: customer.creditLimit,
          );
        }
      }

      final cogs = cart.fold<double>(
        0,
        (sum, line) => sum + line.quantity * products[line.productId]!.costPrice,
      );
      final grossProfit = total - cogs;

      // A gapless sequence — a straight count of every sale ever created
      // (void or not; sales are never deleted) — rather than anything
      // parsed from an existing invoiceNumber, so this can't skip or
      // collide even if the numbering format ever changes.
      final saleCount = countAll();
      final nextSeq =
          await (_db.selectOnly(_db.sales)..addColumns([saleCount]))
              .map((row) => (row.read(saleCount) ?? 0) + 1)
              .getSingle();
      final invoiceNumber = 'INV-${nextSeq.toString().padLeft(6, '0')}';

      final sale = await _db.into(_db.sales).insertReturning(
        SalesCompanion.insert(
          uuid: _uuid.v4(),
          invoiceNumber: invoiceNumber,
          customerId: Value(customerId),
          userId: userId,
          subtotal: Value(subtotal),
          discount: Value(discount),
          total: Value(total),
          amountPaid: Value(amountPaid),
          paymentMethod: paymentMethod,
          cogs: Value(cogs),
          grossProfit: Value(grossProfit),
          createdAt: now,
        ),
      );

      for (final line in cart) {
        final product = products[line.productId]!;

        await _db.into(_db.saleItems).insert(
          SaleItemsCompanion.insert(
            uuid: _uuid.v4(),
            saleId: sale.id,
            productId: line.productId,
            quantity: line.quantity,
            unitPrice: line.price,
            total: line.lineTotal,
            createdAt: now,
          ),
        );

        await _stockMovements.recordMovement(
          productId: line.productId,
          type: 'SALE',
          quantity: -line.quantity,
          unitCost: product.costPrice,
          reference: sale.uuid,
          userId: userId,
        );
      }

      if (customer != null && balanceDue > 0) {
        await (_db.update(
          _db.customers,
        )..where((t) => t.id.equals(customer!.id))).write(
          CustomersCompanion(
            currentBalance: Value(customer.currentBalance + balanceDue),
            updatedAt: Value(now),
          ),
        );
      }

      return sale;
    });
  }

  /// A line's lineTotal is taken as already net of any item-level discount
  /// (the convention [createSale]'s `subtotal` also relies on — CartLine
  /// carries no such field at all, so this is moot for [completeSale]'s
  /// callers), so the only further deduction applied here is
  /// [cartDiscount], allocated across lines in proportion to their share
  /// of [subtotal].
  void _assertNoLineBelowFloor({
    required List<_PriceLine> lines,
    required double subtotal,
    required double cartDiscount,
    required Map<int, Product> products,
  }) {
    for (final line in lines) {
      if (line.quantity <= 0) continue;

      final allocatedCartDiscount = subtotal > 0
          ? cartDiscount * (line.lineTotal / subtotal)
          : 0.0;
      final effectivePrice = (line.lineTotal - allocatedCartDiscount) / line.quantity;

      final product = products[line.productId]!;
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
