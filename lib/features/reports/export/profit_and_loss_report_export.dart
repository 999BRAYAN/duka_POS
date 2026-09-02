import 'dart:typed_data';

import 'package:duka_pos/core/export/csv.dart';
import 'package:duka_pos/core/printing/report_pdf.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/core/web/browser_download.dart';
import 'package:duka_pos/features/reports/domain/models/profit_and_loss_report.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

final _dateFormat = DateFormat('d MMM yyyy');
final _amountFormat = NumberFormat('#,##0.00');

String _subtitle(DateRange range) =>
    // Plain hyphen: the PDF's default font has no glyph for an en dash.
    '${_dateFormat.format(range.start)} - ${_dateFormat.format(range.end)}';

List<(String, double)> _lines(ProfitAndLossReport report) => [
  ('Subtotal', report.subtotal),
  ('Discount', -report.discount),
  ('Net revenue', report.netRevenue),
  ('Cost of goods sold', -report.cogs),
  ('Gross profit', report.grossProfit),
  ('Expenses', -report.expenses),
  ('Net profit', report.netProfit),
];

/// A flat label/value CSV — this report is a statement, not a table of
/// rows, so unlike the sales/inventory exports there is no per-item detail
/// to list underneath it.
String buildProfitAndLossReportCsv(ProfitAndLossReport report, DateRange range) {
  final buffer = StringBuffer()
    ..writeln(buildCsv(['Profit & loss report'], const []))
    ..writeln(buildCsv(['Period', _subtitle(range)], const []))
    ..writeln()
    ..write(
      buildCsv(
        ['Line', 'Amount'],
        [for (final (label, value) in _lines(report)) [label, value.toStringAsFixed(2)]],
      ),
    );
  return buffer.toString();
}

Future<Uint8List> buildProfitAndLossReportPdf(
  ProfitAndLossReport report,
  DateRange range, {
  required PdfPageFormat format,
}) {
  const emphasized = {'Net revenue', 'Gross profit', 'Net profit'};
  return buildStatementPdf(
    title: 'Profit & loss report',
    subtitle: _subtitle(range),
    lines: [
      for (final (label, value) in _lines(report))
        StatementLine(label, _amountFormat.format(value), emphasize: emphasized.contains(label)),
    ],
    format: format,
  );
}

void downloadProfitAndLossReportCsv(ProfitAndLossReport report, DateRange range) {
  triggerBrowserDownload(
    encodeCsvForExcel(buildProfitAndLossReportCsv(report, range)),
    'profit_and_loss_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.csv',
    mimeType: 'text/csv',
  );
}

Future<void> downloadProfitAndLossReportPdf(ProfitAndLossReport report, DateRange range) async {
  final bytes = await buildProfitAndLossReportPdf(report, range, format: PdfPageFormat.a4);
  triggerBrowserDownload(
    bytes,
    'profit_and_loss_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.pdf',
    mimeType: 'application/pdf',
  );
}
