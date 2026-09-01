import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/data/repositories/sales_report_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late SalesReportRepositoryImpl repo;
  late int userId;
  late int productAId;
  late int productBId;
  var idCounter = 0;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = SalesReportRepositoryImpl(db);

    userId = (await db.into(db.users).insertReturning(
      UsersCompanion.insert(
        uuid: 'user-1',
        username: 'cashier',
        passwordHash: 'hash',
        fullName: 'Cashier One',
        role: 'cashier',
        createdAt: DateTime.now(),
      ),
    )).id;

    productAId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(uuid: 'prod-a', name: 'Soda', createdAt: DateTime.now()),
    )).id;
    productBId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(uuid: 'prod-b', name: 'Bread', createdAt: DateTime.now()),
    )).id;
  });

  tearDown(() => db.close());

  Future<int> insertSale({
    required double total,
    required DateTime createdAt,
    String status = 'completed',
  }) async {
    final id = idCounter++;
    final sale = await db.into(db.sales).insertReturning(
      SalesCompanion.insert(
        uuid: 'sale-$id',
        invoiceNumber: 'INV-$id',
        userId: userId,
        subtotal: Value(total),
        total: Value(total),
        paymentMethod: 'cash',
        status: Value(status),
        createdAt: createdAt,
      ),
    );
    return sale.id;
  }

  Future<void> insertSaleItem({
    required int saleId,
    required int productId,
    required double quantity,
    required double total,
  }) {
    final id = idCounter++;
    return db.into(db.saleItems).insert(
      SaleItemsCompanion.insert(
        uuid: 'item-$id',
        saleId: saleId,
        productId: productId,
        quantity: quantity,
        unitPrice: total / quantity,
        total: total,
        createdAt: DateTime.now(),
      ),
    );
  }

  test(
    'sums revenue/count/average over completed sales in range only, '
    'and breaks revenue down by product, highest first',
    () async {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

      final sale1 = await insertSale(total: 300, createdAt: DateTime(2026, 3, 5));
      await insertSaleItem(saleId: sale1, productId: productAId, quantity: 2, total: 200);
      await insertSaleItem(saleId: sale1, productId: productBId, quantity: 1, total: 100);

      final sale2 = await insertSale(total: 150, createdAt: DateTime(2026, 3, 20));
      await insertSaleItem(saleId: sale2, productId: productAId, quantity: 1, total: 150);

      // Outside the range entirely — must not affect any total.
      final outOfRange = await insertSale(total: 999, createdAt: DateTime(2026, 2, 28));
      await insertSaleItem(saleId: outOfRange, productId: productAId, quantity: 5, total: 999);

      // Inside the range but void — a void sale never happened as far as
      // revenue is concerned.
      final voided = await insertSale(
        total: 500,
        createdAt: DateTime(2026, 3, 10),
        status: 'void',
      );
      await insertSaleItem(saleId: voided, productId: productBId, quantity: 3, total: 500);

      final report = await repo.getSalesReport(range);

      expect(report.totalRevenue, 450); // 300 + 150
      expect(report.saleCount, 2);
      expect(report.averageSaleValue, 225);

      expect(report.productBreakdown, hasLength(2));
      expect(report.productBreakdown[0].productId, productAId);
      expect(report.productBreakdown[0].quantitySold, 3); // 2 + 1
      expect(report.productBreakdown[0].revenue, 350); // 200 + 150
      expect(report.productBreakdown[1].productId, productBId);
      expect(report.productBreakdown[1].quantitySold, 1);
      expect(report.productBreakdown[1].revenue, 100);
    },
  );

  test('a range with no completed sales reports all zeros and an empty breakdown', () async {
    final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

    final report = await repo.getSalesReport(range);

    expect(report.totalRevenue, 0);
    expect(report.saleCount, 0);
    expect(report.averageSaleValue, 0);
    expect(report.productBreakdown, isEmpty);
  });
}
