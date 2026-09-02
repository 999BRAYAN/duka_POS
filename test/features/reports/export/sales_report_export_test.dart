import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:duka_pos/features/reports/export/sales_report_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final range = DateRange.forPeriod(Period.today, DateTime(2026, 3, 15));
  final report = SalesReport(
    totalRevenue: 300,
    saleCount: 3,
    averageSaleValue: 100,
    productBreakdown: const [
      ProductRevenue(productId: 1, productName: 'Soda', quantitySold: 5, revenue: 200),
      ProductRevenue(productId: 2, productName: 'Elbow, 90°', quantitySold: 2, revenue: 100),
    ],
  );

  group('buildSalesReportCsv', () {
    test('includes the summary and every product row as plain decimals', () {
      final csv = buildSalesReportCsv(report, range);

      expect(csv, contains('300.00'));
      expect(csv, contains('Soda,5.00,200.00'));
      // A product name containing a comma is quoted rather than splitting
      // into an extra column.
      expect(csv, contains('"Elbow, 90°",2.00,100.00'));
    });
  });

  group('buildSalesReportPdf', () {
    test('produces a valid, non-empty PDF', () async {
      final bytes = await buildSalesReportPdf(report, range, format: PdfPageFormat.a4);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('does not throw for an empty product breakdown', () async {
      final bytes = await buildSalesReportPdf(
        const SalesReport(
          totalRevenue: 0,
          saleCount: 0,
          averageSaleValue: 0,
          productBreakdown: [],
        ),
        range,
        format: PdfPageFormat.a4,
      );

      expect(bytes, isNotEmpty);
    });
  });
}
