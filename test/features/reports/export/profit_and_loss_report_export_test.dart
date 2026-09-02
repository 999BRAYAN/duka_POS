import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';
import 'package:duka_pos/features/reports/export/profit_and_loss_report_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  final range = DateRange.forPeriod(Period.today, DateTime(2026, 3, 15));
  const report = ProfitAndLossReport(subtotal: 1000, discount: 50, cogs: 400, expenses: 100);

  group('buildProfitAndLossReportCsv', () {
    test('every line is a plain-decimal row, derived figures included', () {
      final csv = buildProfitAndLossReportCsv(report, range);

      expect(csv, contains('Subtotal,1000.00'));
      expect(csv, contains('Discount,-50.00'));
      expect(csv, contains('Net revenue,950.00'));
      expect(csv, contains('Gross profit,550.00'));
      expect(csv, contains('Net profit,450.00'));
    });
  });

  group('buildProfitAndLossReportPdf', () {
    test('produces a valid, non-empty PDF', () async {
      final bytes = await buildProfitAndLossReportPdf(report, range, format: PdfPageFormat.a4);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
