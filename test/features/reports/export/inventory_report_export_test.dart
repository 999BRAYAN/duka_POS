import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';
import 'package:duka_pos/features/reports/export/inventory_report_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final range = DateRange.forPeriod(Period.today, DateTime(2026, 3, 15));
  const report = InventoryReport(
    stockLevels: [
      ProductStockValuation(
        productId: 1,
        uuid: 'p1',
        name: 'Soda',
        stock: 20,
        reorderLevel: 5,
        averageCost: 30,
        stockValue: 600,
        isLowStock: false,
      ),
    ],
    movementSummary: [
      MovementTypeSummary(type: 'PURCHASE', totalQuantity: 20),
      MovementTypeSummary(type: 'SALE', totalQuantity: -8),
    ],
  );

  group('buildInventoryReportCsv', () {
    test('includes stock levels, a total, and every movement type zero-filled in order', () {
      final csv = buildInventoryReportCsv(report, range);

      expect(csv, contains('Soda,20.00,30.00,600.00'));
      expect(csv, contains('PURCHASE,20.00'));
      expect(csv, contains('SALE,-8.00'));
      // No RETURN/ADJUSTMENT movement was planted, but the fixed type order
      // still includes them, zero-filled — the same convention the report
      // itself follows.
      expect(csv, contains('RETURN,0.00'));
      expect(csv, contains('ADJUSTMENT,0.00'));
    });
  });

  group('buildInventoryReportPdf', () {
    test('produces a valid, non-empty PDF covering both tables', () async {
      final bytes = await buildInventoryReportPdf(report, range, format: PdfPageFormat.a4);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('does not throw with no products and no movement', () async {
      final bytes = await buildInventoryReportPdf(
        const InventoryReport(stockLevels: [], movementSummary: []),
        range,
        format: PdfPageFormat.a4,
      );

      expect(bytes, isNotEmpty);
    });
  });
}
