import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:duka_pos/features/purchases/domain/exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late PurchaseRepositoryImpl repo;
  late int productId;
  late int supplierId;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = PurchaseRepositoryImpl(db, StockMovementRepositoryImpl(db));

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(5),
        createdAt: DateTime.now(),
      ),
    )).id;

    supplierId = (await db.into(db.suppliers).insertReturning(
      SuppliersCompanion.insert(
        uuid: 'sup-1',
        name: 'Acme',
        createdAt: DateTime.now(),
      ),
    )).id;

    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'manager',
        passwordHash: 'hash',
        fullName: 'Manager One',
        role: 'manager',
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  PurchaseItemsCompanion item({required double quantity, required double total}) {
    return PurchaseItemsCompanion.insert(
      uuid: 'item-placeholder',
      purchaseId: 0,
      productId: productId,
      quantity: quantity,
      unitCost: total / quantity,
      total: total,
      createdAt: DateTime.now(),
    );
  }

  test('createPurchase does not change stock; status is pending', () async {
    final purchase = await repo.createPurchase(
      supplierId: supplierId,
      userId: userId,
      items: [item(quantity: 10, total: 300)],
    );

    expect(purchase.status, 'pending');
    expect(purchase.total, 300);

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 5);
  });

  test('markPurchaseReceived increments stock and records a PURCHASE movement', () async {
    final purchase = await repo.createPurchase(
      supplierId: supplierId,
      userId: userId,
      items: [item(quantity: 10, total: 300)],
    );

    await repo.markPurchaseReceived(purchase.uuid);

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 15);

    final received = await repo.getPurchaseByUuid(purchase.uuid);
    expect(received?.status, 'received');

    final movements = await (db.select(
      db.stockMovements,
    )..where((t) => t.productId.equals(productId))).get();
    expect(movements.single.type, 'PURCHASE');
    expect(movements.single.quantity, 10);
    expect(movements.single.unitCost, 30);
    expect(movements.single.userId, userId);
  });

  test('markPurchaseReceived twice throws InvalidPurchaseStatusException', () async {
    final purchase = await repo.createPurchase(
      supplierId: supplierId,
      userId: userId,
      items: [item(quantity: 10, total: 300)],
    );
    await repo.markPurchaseReceived(purchase.uuid);

    expect(
      () => repo.markPurchaseReceived(purchase.uuid),
      throwsA(isA<InvalidPurchaseStatusException>()),
    );
  });

  test('cancelPurchase on a received purchase throws', () async {
    final purchase = await repo.createPurchase(
      supplierId: supplierId,
      userId: userId,
      items: [item(quantity: 10, total: 300)],
    );
    await repo.markPurchaseReceived(purchase.uuid);

    expect(
      () => repo.cancelPurchase(purchase.uuid),
      throwsA(isA<InvalidPurchaseStatusException>()),
    );
  });

  test('cancelPurchase on a pending purchase sets status to cancelled', () async {
    final purchase = await repo.createPurchase(
      supplierId: supplierId,
      userId: userId,
      items: [item(quantity: 10, total: 300)],
    );

    await repo.cancelPurchase(purchase.uuid);

    final cancelled = await repo.getPurchaseByUuid(purchase.uuid);
    expect(cancelled?.status, 'cancelled');
  });

  group('receiveStock', () {
    test('computes the quantity-weighted average cost and updates stock', () async {
      await (db.update(
        db.products,
      )..where((t) => t.id.equals(productId))).write(
        const ProductsCompanion(stock: Value(10), costPrice: Value(20)),
      );

      await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)], // unitCost 30
        paymentStatus: 'paid',
        amountPaid: 300,
      );

      final product = await (db.select(
        db.products,
      )..where((t) => t.id.equals(productId))).getSingle();
      expect(product.stock, 20);
      expect(product.costPrice, 25); // (10*20 + 10*30) / 20
    });

    test('records a PURCHASE stock movement referencing the purchase', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'paid',
        amountPaid: 300,
      );

      final movements = await (db.select(
        db.stockMovements,
      )..where((t) => t.productId.equals(productId))).get();
      expect(movements.single.type, 'PURCHASE');
      expect(movements.single.quantity, 10);
      expect(movements.single.unitCost, 30);
      expect(movements.single.reference, purchase.uuid);
      expect(movements.single.userId, userId);
    });

    test('marks the purchase received and stores the payment status', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'partial',
        amountPaid: 200,
      );

      expect(purchase.status, 'received');
      expect(purchase.paymentStatus, 'partial');
      expect(purchase.total, 300);
    });

    test('adds the shortfall to Supplier.balance when underpaid', () async {
      await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'partial',
        amountPaid: 200,
      );

      final supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(supplierId))).getSingle();
      expect(supplier.balance, 100);
    });

    test('leaves Supplier.balance unchanged when paid in full', () async {
      await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'paid',
        amountPaid: 300,
      );

      final supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(supplierId))).getSingle();
      expect(supplier.balance, 0);
    });

    test('rejects an unknown payment status and writes nothing', () async {
      await expectLater(
        repo.receiveStock(
          supplierId: supplierId,
          userId: userId,
          items: [item(quantity: 10, total: 300)],
          paymentStatus: 'overdue',
          amountPaid: 0,
        ),
        throwsA(isA<InvalidPaymentStatusException>()),
      );

      final purchases = await repo.watchPurchases().first;
      expect(purchases, isEmpty);
    });
  });

  group('recordPayment', () {
    test('a partial top-up moves paymentStatus to paid once it covers the total', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'partial',
        amountPaid: 200,
      );

      final updated = await repo.recordPayment(purchase.uuid, amount: 100);

      expect(updated.amountPaid, 300);
      expect(updated.paymentStatus, 'paid');
    });

    test('a payment that still leaves a balance stays partial', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'unpaid',
        amountPaid: 0,
      );

      final updated = await repo.recordPayment(purchase.uuid, amount: 120);

      expect(updated.amountPaid, 120);
      expect(updated.paymentStatus, 'partial');
    });

    test('reduces Supplier.balance by the amount paid', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'unpaid',
        amountPaid: 0,
      );

      await repo.recordPayment(purchase.uuid, amount: 300);

      final supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(supplierId))).getSingle();
      expect(supplier.balance, 0);
    });

    test('rejects a payment exceeding what is owed and writes nothing', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'partial',
        amountPaid: 200,
      );

      await expectLater(
        repo.recordPayment(purchase.uuid, amount: 200),
        throwsA(isA<InvalidPurchasePaymentException>()),
      );

      final unchanged = await repo.getPurchaseByUuid(purchase.uuid);
      expect(unchanged?.amountPaid, 200);
      expect(unchanged?.paymentStatus, 'partial');
    });

    test('rejects a non-positive amount', () async {
      final purchase = await repo.receiveStock(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
        paymentStatus: 'unpaid',
        amountPaid: 0,
      );

      await expectLater(
        repo.recordPayment(purchase.uuid, amount: 0),
        throwsA(isA<InvalidPurchasePaymentException>()),
      );
    });

    test('refuses a payment against a purchase still pending', () async {
      final purchase = await repo.createPurchase(
        supplierId: supplierId,
        userId: userId,
        items: [item(quantity: 10, total: 300)],
      );

      await expectLater(
        repo.recordPayment(purchase.uuid, amount: 100),
        throwsA(isA<InvalidPurchaseStatusException>()),
      );
    });
  });
}
