import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
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
    repo = PurchaseRepositoryImpl(db);

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
}
