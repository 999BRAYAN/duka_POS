import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_valuation_repository_impl.dart';
import 'package:duka_pos/features/reports/data/repositories/inventory_report_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late InventoryReportRepositoryImpl repo;
  late StockMovementRepositoryImpl movements;
  late int productId;

  setUp(() async {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    movements = StockMovementRepositoryImpl(db);
    repo = InventoryReportRepositoryImpl(db, StockValuationRepositoryImpl(db));

    productId = (await db.into(db.products).insertReturning(
      ProductsCompanion.insert(
        uuid: 'prod-1',
        name: 'Soda',
        costPrice: const Value(50),
        createdAt: DateTime.now(),
      ),
    )).id;
  });

  tearDown(() => db.close());

  // recordMovement stamps createdAt with DateTime.now() and doesn't expose
  // it as a parameter — backdating afterwards gives the test deterministic
  // control over what falls inside vs. outside the report's DateRange.
  Future<void> backdateLatestMovement(DateTime date) async {
    final latest = await (db.select(
      db.stockMovements,
    )..orderBy([(t) => OrderingTerm.desc(t.id)])..limit(1)).getSingle();
    await (db.update(
      db.stockMovements,
    )..where((t) => t.id.equals(latest.id))).write(StockMovementsCompanion(createdAt: Value(date)));
  }

  test(
    'reports current stock levels (reusing StockValuationRepository) alongside '
    'movement totals by type, scoped to the given range',
    () async {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

      await movements.recordMovement(
        productId: productId,
        type: 'PURCHASE',
        quantity: 20,
        unitCost: 40,
      );
      await backdateLatestMovement(DateTime(2026, 3, 5));

      await movements.recordMovement(productId: productId, type: 'SALE', quantity: -5);
      await backdateLatestMovement(DateTime(2026, 3, 10));

      await movements.recordMovement(productId: productId, type: 'RETURN', quantity: 2);
      await backdateLatestMovement(DateTime(2026, 3, 12));

      await movements.recordMovement(productId: productId, type: 'ADJUSTMENT', quantity: -1);
      await backdateLatestMovement(DateTime(2026, 3, 20));

      // Outside the range entirely, but still a PURCHASE — must not be
      // folded into the in-range PURCHASE total, and (unlike the movement
      // summary) *should* still count toward the live average-cost figure,
      // since stock levels are a snapshot of right now, not history.
      await movements.recordMovement(
        productId: productId,
        type: 'PURCHASE',
        quantity: 100,
        unitCost: 60,
      );
      await backdateLatestMovement(DateTime(2026, 2, 1));

      final report = await repo.getInventoryReport(range);

      final level = report.stockLevels.singleWhere((l) => l.productId == productId);
      expect(level.stock, 116); // 20 - 5 + 2 - 1 + 100
      final expectedAverageCost = (20 * 40 + 100 * 60) / (20 + 100);
      expect(level.averageCost, closeTo(expectedAverageCost, 0.001));
      expect(level.stockValue, closeTo(level.stock * level.averageCost, 0.001));

      final byType = {for (final m in report.movementSummary) m.type: m.totalQuantity};
      expect(byType, hasLength(4)); // the out-of-range PURCHASE adds no new group
      expect(byType['PURCHASE'], 20);
      expect(byType['SALE'], -5);
      expect(byType['RETURN'], 2);
      expect(byType['ADJUSTMENT'], -1);
    },
  );

  test(
    'a range with no movements has an empty movement summary but still reports current stock',
    () async {
      final range = DateRange.forPeriod(Period.month, DateTime(2026, 3, 15));

      await movements.recordMovement(productId: productId, type: 'PURCHASE', quantity: 10);
      await backdateLatestMovement(DateTime(2026, 1, 1)); // outside the range

      final report = await repo.getInventoryReport(range);

      expect(report.movementSummary, isEmpty);
      expect(report.stockLevels, hasLength(1));
      expect(report.stockLevels.single.stock, 10);
    },
  );
}
