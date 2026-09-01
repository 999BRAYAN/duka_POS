import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decorates a real [StockMovementRepository] so the *first* stock deduction
/// still actually runs (stock and the audit row are genuinely written
/// inside the surrounding `db.transaction()`), then throws — simulating a
/// failure partway through `completeSale`, after stock has moved but before
/// the customer-balance write that follows the cart-line loop.
class _ThrowsAfterFirstMovement implements StockMovementRepository {
  _ThrowsAfterFirstMovement(this._real);
  final StockMovementRepository _real;

  @override
  Future<StockMovement> recordMovement({
    required int productId,
    required String type,
    required double quantity,
    double? unitCost,
    String? reference,
    String? notes,
    int? userId,
  }) async {
    await _real.recordMovement(
      productId: productId,
      type: type,
      quantity: quantity,
      unitCost: unitCost,
      reference: reference,
      notes: notes,
      userId: userId,
    );
    throw Exception('Simulated failure after stock deduction');
  }

  @override
  Stream<List<StockMovement>> watchMovementsForProduct(int productId) =>
      _real.watchMovementsForProduct(productId);

  @override
  Stream<List<StockMovement>> watchRecentMovements({int limit = 50}) =>
      _real.watchRecentMovements(limit: limit);
}

void main() {
  late DukaDatabase db;
  late SaleRepositoryImpl repo;
  late int productId;
  late int userId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = SaleRepositoryImpl(
      db,
      StockMovementRepositoryImpl(db),
      CreditRepositoryImpl(db),
    );

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

  group('voidSale and the customer balance', () {
    late int customerId;

    setUp(() async {
      final customer = await db.into(db.customers).insertReturning(
        CustomersCompanion.insert(
          uuid: 'cust-void',
          name: 'Joseph Kamau',
          creditLimit: const Value(5000),
          currentBalance: const Value(0),
          createdAt: DateTime.now(),
        ),
      );
      customerId = customer.id;
    });

    Future<Customer> readCustomer() => (db.select(
      db.customers,
    )..where((t) => t.id.equals(customerId))).getSingle();

    Future<double> readStock() async =>
        (await (db.select(db.products)..where((t) => t.id.equals(productId))).getSingle()).stock;

    test('voiding a credit sale takes the debt back off the customer', () async {
      final stockBefore = await readStock();
      final balanceBefore = (await readCustomer()).currentBalance;

      final sale = await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 3, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 100,
      );

      // The sale left 140 owing, which must be on the customer first —
      // otherwise the reversal below would prove nothing.
      expect((await readCustomer()).currentBalance, 140);

      await repo.voidSale(sale.uuid);

      expect(
        (await readCustomer()).currentBalance,
        balanceBefore,
        reason: 'a voided sale must not leave the customer owing for it',
      );
      expect(await readStock(), stockBefore);
    });

    test('voiding a fully-paid sale leaves the balance untouched', () async {
      await db.into(db.creditTransactions).insert(
        CreditTransactionsCompanion.insert(
          uuid: 'ct-opening',
          customerId: customerId,
          type: 'CHARGE',
          amount: 900,
          balanceAfter: 900,
          createdAt: DateTime.now(),
        ),
      );
      await (db.update(db.customers)..where((t) => t.id.equals(customerId))).write(
        const CustomersCompanion(currentBalance: Value(900)),
      );

      final sale = await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 2, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 160,
      );

      await repo.voidSale(sale.uuid);

      expect(
        (await readCustomer()).currentBalance,
        900,
        reason: 'this sale never charged the customer, so voiding it must not credit them',
      );
    });

    test('the reversal is floored at zero when payments already cleared the debt', () async {
      final sale = await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 3, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 100,
      );

      // The customer settles up before anyone notices the sale was wrong.
      await (db.update(db.customers)..where((t) => t.id.equals(customerId))).write(
        const CustomersCompanion(currentBalance: Value(0)),
      );

      await repo.voidSale(sale.uuid);

      expect(
        (await readCustomer()).currentBalance,
        0,
        reason: 'the shop never ends up owing the customer money',
      );
    });

    test('a credit sale leaves a CHARGE row, and voiding it leaves a REVERSAL', () async {
      final sale = await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 3, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 100,
      );

      var rows = await (db.select(
        db.creditTransactions,
      )..where((t) => t.customerId.equals(customerId))).get();
      expect(rows, hasLength(1));
      expect(rows.single.type, 'CHARGE');
      expect(rows.single.amount, 140);
      expect(rows.single.saleId, sale.id, reason: 'the charge points back at its sale');
      expect(rows.single.balanceAfter, 140);

      await repo.voidSale(sale.uuid);

      rows = await (db.select(db.creditTransactions)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get();
      expect(rows.map((r) => r.type), ['CHARGE', 'REVERSAL']);
      expect(rows.last.amount, 140);
      expect(rows.last.balanceAfter, 0);

      // The whole point: the balance can be rebuilt from these rows alone.
      final rebuilt = rows.fold<double>(
        0,
        (sum, r) => r.type == 'CHARGE' ? sum + r.amount : sum - r.amount,
      );
      expect(rebuilt, (await readCustomer()).currentBalance);
    });

    test('a fully-paid sale writes no credit transaction at all', () async {
      await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 2, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 160,
      );

      final rows = await (db.select(
        db.creditTransactions,
      )..where((t) => t.customerId.equals(customerId))).get();
      expect(rows, isEmpty, reason: 'nothing was owed, so nothing was charged');
    });

    test('a sale cannot be voided twice', () async {
      final sale = await repo.completeSale(
        cart: [CartLine(productId: productId, name: 'Soda', quantity: 3, price: 80)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        amountPaid: 100,
      );

      await repo.voidSale(sale.uuid);
      final stockAfterVoid = await readStock();

      await expectLater(
        repo.voidSale(sale.uuid),
        throwsA(isA<SaleAlreadyVoidException>()),
      );

      expect(await readStock(), stockAfterVoid, reason: 'stock is not returned twice');
      expect((await readCustomer()).currentBalance, 0);
    });
  });

  group('createSale price floor', () {
    Future<int> addProduct(String name, {required double minSellingPrice}) async {
      final product = await db.into(db.products).insertReturning(
        ProductsCompanion.insert(
          uuid: 'prod-$name',
          name: name,
          stock: const Value(50),
          minSellingPrice: Value(minSellingPrice),
          createdAt: DateTime.now(),
        ),
      );
      return product.id;
    }

    test('rejects a line priced below its product\'s minSellingPrice', () async {
      final capId = await addProduct('Bottle Cap', minSellingPrice: 60);

      await expectLater(
        repo.createSale(
          invoiceNumber: 'INV-1',
          userId: userId,
          items: [
            SaleItemsCompanion.insert(
              uuid: 'item-placeholder',
              saleId: 0,
              productId: capId,
              quantity: 3,
              unitPrice: 50,
              total: 150, // 50/unit, below the 60 floor
              createdAt: DateTime.now(),
            ),
          ],
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<PriceBelowFloorException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('Bottle Cap'), contains('60.00')),
          ),
        ),
      );

      expect(await repo.watchSales().first, isEmpty);
    });

    test('allows a line priced exactly at the floor', () async {
      final capId = await addProduct('Bottle Cap', minSellingPrice: 60);

      final sale = await repo.createSale(
        invoiceNumber: 'INV-2',
        userId: userId,
        items: [
          SaleItemsCompanion.insert(
            uuid: 'item-placeholder',
            saleId: 0,
            productId: capId,
            quantity: 2,
            unitPrice: 60,
            total: 120,
            createdAt: DateTime.now(),
          ),
        ],
        paymentMethod: 'cash',
      );

      expect(sale.total, 120);
    });

    test('an item-level discount that pushes the effective price below the floor is caught', () async {
      final capId = await addProduct('Bottle Cap', minSellingPrice: 90);

      // Listed at 100/unit, but a 20 line-level discount brings the net
      // total to 80 for the single unit — below the 90 floor even though
      // unitPrice alone looks fine.
      await expectLater(
        repo.createSale(
          invoiceNumber: 'INV-3',
          userId: userId,
          items: [
            SaleItemsCompanion.insert(
              uuid: 'item-placeholder',
              saleId: 0,
              productId: capId,
              quantity: 1,
              unitPrice: 100,
              discount: const Value(20),
              total: 80,
              createdAt: DateTime.now(),
            ),
          ],
          paymentMethod: 'cash',
        ),
        throwsA(isA<PriceBelowFloorException>()),
      );
    });

    test('a proportionally-allocated cart-level discount that pushes one line below the floor is caught', () async {
      final cheapId = await addProduct('Cheap Item', minSellingPrice: 60);
      final pricierId = await addProduct('Pricier Item', minSellingPrice: 150);

      // subtotal 300; a 90 cart discount allocates 30 to the 100-total line
      // (effective 70, fine against a 60 floor) and 60 to the 200-total
      // line (effective 140, below its 150 floor).
      await expectLater(
        repo.createSale(
          invoiceNumber: 'INV-4',
          userId: userId,
          items: [
            SaleItemsCompanion.insert(
              uuid: 'item-1',
              saleId: 0,
              productId: cheapId,
              quantity: 1,
              unitPrice: 100,
              total: 100,
              createdAt: DateTime.now(),
            ),
            SaleItemsCompanion.insert(
              uuid: 'item-2',
              saleId: 0,
              productId: pricierId,
              quantity: 1,
              unitPrice: 200,
              total: 200,
              createdAt: DateTime.now(),
            ),
          ],
          discount: 90,
          paymentMethod: 'cash',
        ),
        throwsA(
          isA<PriceBelowFloorException>().having(
            (e) => e.toString(),
            'message',
            contains('Pricier Item'),
          ),
        ),
      );

      expect(await repo.watchSales().first, isEmpty);
    });

    test('succeeds when a cart-level discount still keeps every line at or above its floor', () async {
      final cheapId = await addProduct('Cheap Item', minSellingPrice: 60);
      final pricierId = await addProduct('Pricier Item', minSellingPrice: 100);

      // Same 90 discount, but this time proportionally allocated as 30/60
      // leaves both lines (70 and 140) at or above their floors.
      final sale = await repo.createSale(
        invoiceNumber: 'INV-5',
        userId: userId,
        items: [
          SaleItemsCompanion.insert(
            uuid: 'item-1',
            saleId: 0,
            productId: cheapId,
            quantity: 1,
            unitPrice: 100,
            total: 100,
            createdAt: DateTime.now(),
          ),
          SaleItemsCompanion.insert(
            uuid: 'item-2',
            saleId: 0,
            productId: pricierId,
            quantity: 1,
            unitPrice: 200,
            total: 200,
            createdAt: DateTime.now(),
          ),
        ],
        discount: 90,
        paymentMethod: 'cash',
      );

      expect(sale.total, 210); // 300 - 90
      final movements = await db.select(db.stockMovements).get();
      expect(movements, hasLength(2));
    });
  });

  group('completeSale', () {
    Future<int> addProduct(
      String name, {
      double stock = 50,
      double costPrice = 0,
      double minSellingPrice = 0,
    }) async {
      final product = await db.into(db.products).insertReturning(
        ProductsCompanion.insert(
          uuid: 'prod-$name',
          name: name,
          stock: Value(stock),
          costPrice: Value(costPrice),
          minSellingPrice: Value(minSellingPrice),
          createdAt: DateTime.now(),
        ),
      );
      return product.id;
    }

    Future<int> addCustomer(
      String name, {
      double creditLimit = 0,
      double currentBalance = 0,
    }) async {
      final customer = await db.into(db.customers).insertReturning(
        CustomersCompanion.insert(
          uuid: 'cust-$name',
          name: name,
          creditLimit: Value(creditLimit),
          currentBalance: Value(currentBalance),
          createdAt: DateTime.now(),
        ),
      );
      return customer.id;
    }

    test('happy path: decrements stock, records a SALE movement, computes cogs/grossProfit', () async {
      final sodaId = await addProduct('Soda', stock: 20, costPrice: 40);

      final sale = await repo.completeSale(
        cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 3)],
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 210,
      );

      expect(sale.invoiceNumber, 'INV-000001');
      expect(sale.subtotal, 210);
      expect(sale.total, 210);
      expect(sale.cogs, 120); // 3 * 40
      expect(sale.grossProfit, 90); // 210 - 120

      final product = await (db.select(
        db.products,
      )..where((t) => t.id.equals(sodaId))).getSingle();
      expect(product.stock, 17);

      final movements = await (db.select(
        db.stockMovements,
      )..where((t) => t.productId.equals(sodaId))).get();
      expect(movements.single.type, 'SALE');
      expect(movements.single.quantity, -3);
      expect(movements.single.unitCost, 40);
    });

    test('receipt numbers are gapless and sequential across calls', () async {
      final sodaId = await addProduct('Soda', stock: 20);

      final first = await repo.completeSale(
        cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 70,
      );
      final second = await repo.completeSale(
        cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 70,
      );

      expect(first.invoiceNumber, 'INV-000001');
      expect(second.invoiceNumber, 'INV-000002');
    });

    test('rejects a cart line that exceeds current stock and writes nothing', () async {
      final sodaId = await addProduct('Soda', stock: 2);

      await expectLater(
        repo.completeSale(
          cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 5)],
          userId: userId,
          paymentMethod: 'cash',
          amountPaid: 350,
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await repo.watchSales().first, isEmpty);
      final product = await (db.select(
        db.products,
      )..where((t) => t.id.equals(sodaId))).getSingle();
      expect(product.stock, 2);
    });

    test('rejects a line priced below its minSellingPrice', () async {
      final capId = await addProduct('Bottle Cap', stock: 10, minSellingPrice: 60);

      await expectLater(
        repo.completeSale(
          cart: [CartLine(productId: capId, name: 'Bottle Cap', price: 50, quantity: 1)],
          userId: userId,
          paymentMethod: 'cash',
          amountPaid: 50,
        ),
        throwsA(isA<PriceBelowFloorException>()),
      );
    });

    test('credit sale with no customer is rejected', () async {
      final sodaId = await addProduct('Soda', stock: 10);

      await expectLater(
        repo.completeSale(
          cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
          userId: userId,
          paymentMethod: 'credit',
        ),
        throwsA(isA<CustomerRequiredForCreditException>()),
      );
    });

    test('credit sale that would exceed the customer\'s credit limit is rejected', () async {
      final sodaId = await addProduct('Soda', stock: 10);
      final customerId = await addCustomer('Jane', creditLimit: 100, currentBalance: 80);

      await expectLater(
        repo.completeSale(
          cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
          customerId: customerId,
          userId: userId,
          paymentMethod: 'credit',
        ),
        throwsA(isA<CreditLimitExceededException>()),
      );

      expect(await repo.watchSales().first, isEmpty);
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();
      expect(customer.currentBalance, 80); // unchanged
    });

    test(
      'a cash sale left with a balance due is checked against the credit limit too, '
      'not just an explicit "credit" payment method',
      () async {
        final sodaId = await addProduct('Soda', stock: 10);
        final customerId = await addCustomer('Jane', creditLimit: 100, currentBalance: 80);

        await expectLater(
          repo.completeSale(
            cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
            customerId: customerId,
            userId: userId,
            paymentMethod: 'cash',
            amountPaid: 0, // the full 70 is left as a balance due
          ),
          throwsA(isA<CreditLimitExceededException>()),
        );

        expect(await repo.watchSales().first, isEmpty);
        final customer = await (db.select(
          db.customers,
        )..where((t) => t.id.equals(customerId))).getSingle();
        expect(customer.currentBalance, 80); // unchanged
      },
    );

    test('overrideCreditLimit bypasses the limit check', () async {
      final sodaId = await addProduct('Soda', stock: 10);
      final customerId = await addCustomer('Jane', creditLimit: 100, currentBalance: 80);

      final sale = await repo.completeSale(
        cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 1)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'credit',
        overrideCreditLimit: true,
      );

      expect(sale.total, 70);
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();
      expect(customer.currentBalance, 150); // 80 + 70 unpaid
    });

    test('adds any unpaid balance to Customers.balance regardless of payment method', () async {
      final sodaId = await addProduct('Soda', stock: 10);
      final customerId = await addCustomer('Jane', creditLimit: 1000);

      await repo.completeSale(
        cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 2)],
        customerId: customerId,
        userId: userId,
        paymentMethod: 'cash',
        amountPaid: 100, // 40 short of the 140 total
      );

      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(customerId))).getSingle();
      expect(customer.currentBalance, 40);
    });

    test('an empty cart is rejected', () {
      expect(
        () => repo.completeSale(cart: const [], userId: userId, paymentMethod: 'cash'),
        throwsArgumentError,
      );
    });

    test(
      'a failure after stock has been deducted rolls back the whole transaction: '
      'stock, sales, and customer balance are all left unchanged',
      () async {
        final sodaId = await addProduct('Soda', stock: 20, costPrice: 40);
        final customerId = await addCustomer('Jane', creditLimit: 1000, currentBalance: 10);

        final flakyRepo = SaleRepositoryImpl(
          db,
          _ThrowsAfterFirstMovement(StockMovementRepositoryImpl(db)),
          CreditRepositoryImpl(db),
        );

        await expectLater(
          flakyRepo.completeSale(
            cart: [CartLine(productId: sodaId, name: 'Soda', price: 70, quantity: 3)],
            customerId: customerId,
            userId: userId,
            paymentMethod: 'cash',
            amountPaid: 100, // leaves a balance due, so the customer row would be touched
          ),
          throwsException,
        );

        final product = await (db.select(
          db.products,
        )..where((t) => t.id.equals(sodaId))).getSingle();
        expect(product.stock, 20, reason: 'the stock deduction itself must have rolled back');

        expect(await repo.watchSales().first, isEmpty, reason: 'no sale row should be committed');

        final movements = await db.select(db.stockMovements).get();
        expect(movements, isEmpty, reason: 'the stock movement audit row must roll back too');

        final customer = await (db.select(
          db.customers,
        )..where((t) => t.id.equals(customerId))).getSingle();
        expect(customer.currentBalance, 10, reason: 'never reached — but confirm it stayed put');
      },
    );
  });
}
