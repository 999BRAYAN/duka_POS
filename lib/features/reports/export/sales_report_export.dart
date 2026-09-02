import 'dart:typed_data';

import 'package:duka_pos/core/export/csv.dart';
import 'package:duka_pos/core/printing/report_pdf.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/core/web/browser_download.dart';
import 'package:duka_pos/features/reports/domain/models/sales_report.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _amountFormat = NumberFormat('#,##0.00');

String _subtitle(DateRange range) =>
    // A plain hyphen, not an en dash: the PDF's default font (Helvetica)
    // has no glyph for U+2013 and would render it as a missing-character
    // box.
    '${_dateFormat.format(range.start)} - ${_dateFormat.format(range.end)}';

/// Builds the sales report as CSV text: a small summary block, a blank
/// line, then the per-product breakdown table — plain decimals throughout
/// (no thousands separators), since a spreadsheet should read these as
/// numbers, not as formatted text. See buildCsv's own doc for why.
String buildSalesReportCsv(SalesReport report, DateRange range) {
  final buffer = StringBuffer()
    ..writeln(buildCsv(['Sales report'], const []))
    ..writeln(buildCsv(['Period', _subtitle(range)], const []))
    ..writeln(
      buildCsv(
        ['Total revenue', 'Sales', 'Average sale'],
        [
          [
            report.totalRevenue.toStringAsFixed(2),
            report.saleCount,
            report.averageSaleValue.toStringAsFixed(2),
          ],
        ],
      ),
    )
    ..writeln()
    ..write(
      buildCsv(
        ['Product', 'Quantity sold', 'Revenue'],
        [
          for (final row in report.productBreakdown)
            [row.productName, row.quantitySold.toStringAsFixed(2), row.revenue.toStringAsFixed(2)],
        ],
      ),
    );
  return buffer.toString();
}

Future<Uint8List> buildSalesReportPdf(
  SalesReport report,
  DateRange range, {
  required PdfPageFormat format,
}) {
  return buildTablePdf(
    title: 'Sales report',
    // Plain " | " separators: the PDF's default font has no glyph for a
    // middle dot.
    subtitle:
        '${_subtitle(range)}  |  ${report.saleCount} sale(s)  |  '
        'Total ${_amountFormat.format(report.totalRevenue)}  |  '
        'Average ${_amountFormat.format(report.averageSaleValue)}',
    headers: const ['Product', 'Quantity sold', 'Revenue'],
    rows: [
      for (final row in report.productBreakdown)
        [row.productName, _amountFormat.format(row.quantitySold), _amountFormat.format(row.revenue)],
    ],
    totalsRow: ['Total revenue', _amountFormat.format(report.totalRevenue)],
    format: format,
  );
}

/// Downloads the CSV directly — no picker, no print dialog, matching every
/// other "Download CSV" export in the app.
void downloadSalesReportCsv(SalesReport report, DateRange range) {
  triggerBrowserDownload(
    encodeCsvForExcel(buildSalesReportCsv(report, range)),
    'sales_report_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.csv',
    mimeType: 'text/csv',
  );
}

Future<void> downloadSalesReportPdf(SalesReport report, DateRange range) async {
  final bytes = await buildSalesReportPdf(report, range, format: PdfPageFormat.a4);
  triggerBrowserDownload(
    bytes,
    'sales_report_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.pdf',
    mimeType: 'application/pdf',
  );
}
