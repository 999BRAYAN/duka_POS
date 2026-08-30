import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late SaleRepositoryImpl repo;
  late int productId;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = SaleRepositoryImpl(db);

    final product = await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        stock: const Value(20),
        createdAt: DateTime.now(),
      ),
    );
    productId = product.id;

    final user = await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    );
    userId = user.id;
  });

  tearDown(() => db.close());

  SaleItemsCompanion item({required double quantity, required double total}) {
    return SaleItemsCompanion.insert(
      uuid: 'item-placeholder',
      saleId: 0,
      productId: productId,
      quantity: quantity,
      unitPrice: total / quantity,
      total: total,
      createdAt: DateTime.now(),
    );
  }

  test('createSale decrements product stock and records a SALE movement', () async {
    final sale = await repo.createSale(
      invoiceNumber: 'INV-1',
      userId: userId,
      items: [item(quantity: 3, total: 240)],
      paymentMethod: 'cash',
      amountPaid: 240,
    );

    expect(sale.total, 240);
    expect(sale.subtotal, 240);

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 17);

    final movements = await (db.select(
      db.stockMovements,
    )..where((t) => t.productId.equals(productId))).get();
    expect(movements, hasLength(1));
    expect(movements.single.type, 'SALE');
    expect(movements.single.quantity, -3);
  });

  test('voidSale restores stock and records a RETURN movement', () async {
    final sale = await repo.createSale(
      invoiceNumber: 'INV-2',
      userId: userId,
      items: [item(quantity: 3, total: 240)],
      paymentMethod: 'cash',
      amountPaid: 240,
    );

    await repo.voidSale(sale.uuid);

    final product = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    expect(product.stock, 20);

    final voided = await repo.getSaleByUuid(sale.uuid);
    expect(voided?.status, 'void');

    final movements = await (db.select(
      db.stockMovements,
    )..where((t) => t.productId.equals(productId))).get();
    expect(movements.map((m) => m.type), containsAll(['SALE', 'RETURN']));
  });
}
