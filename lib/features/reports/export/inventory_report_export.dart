import 'dart:typed_data';

import 'package:duka_pos/core/export/csv.dart';
import 'package:duka_pos/core/utilities/date_range.dart';
import 'package:duka_pos/core/web/browser_download.dart';
import 'package:duka_pos/features/reports/domain/models/inventory_report.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

final _dateFormat = DateFormat('d MMM yyyy');
final _amountFormat = NumberFormat('#,##0.00');

const _movementTypeOrder = ['PURCHASE', 'SALE', 'RETURN', 'ADJUSTMENT'];

String _subtitle(DateRange range) =>
    // Plain hyphen: the PDF's default font has no glyph for an en dash.
    '${_dateFormat.format(range.start)} - ${_dateFormat.format(range.end)}';

/// Movement summary rows in [_movementTypeOrder], zero-filled for a type
/// with no activity — same fixed-order convention ReportsScreen's own bar
/// chart uses, so a type's position doesn't shift between exports.
List<(String, double)> _movementRows(InventoryReport report) {
  final byType = {for (final s in report.movementSummary) s.type: s.totalQuantity};
  return [for (final type in _movementTypeOrder) (type, byType[type] ?? 0)];
}

/// Two tables in one CSV — stock levels, then a blank line, then stock
/// movement — since both are "inventory" but neither is a subset of the
/// other.
String buildInventoryReportCsv(InventoryReport report, DateRange range) {
  final buffer = StringBuffer()
    ..writeln(buildCsv(['Inventory report'], const []))
    ..writeln(buildCsv(['Period', _subtitle(range)], const []))
    ..writeln()
    ..writeln(
      buildCsv(
        ['Product', 'Stock', 'Avg cost', 'Stock value'],
        [
          for (final level in report.stockLevels)
            [
              level.name,
              level.stock.toStringAsFixed(2),
              level.averageCost.toStringAsFixed(2),
              level.stockValue.toStringAsFixed(2),
            ],
        ],
      ),
    )
    ..writeln()
    ..write(
      buildCsv(
        ['Movement type', 'Net quantity'],
        [for (final (type, quantity) in _movementRows(report)) [type, quantity.toStringAsFixed(2)]],
      ),
    );
  return buffer.toString();
}

/// Built directly with pw widgets rather than report_pdf.dart's
/// buildTablePdf: this report has two distinct tables (stock levels,
/// movement summary), and that helper only carries one.
Future<Uint8List> buildInventoryReportPdf(
  InventoryReport report,
  DateRange range, {
  required PdfPageFormat format,
}) async {
  final document = pw.Document();
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final totalStockValue = report.stockLevels.fold<double>(0, (sum, l) => sum + l.stockValue);

  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      build: (context) => [
        pw.Text('Inventory report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(_subtitle(range), style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 16),
        pw.Text('Stock levels', style: headerStyle),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const ['Product', 'Stock', 'Avg cost', 'Stock value'],
          data: [
            for (final level in report.stockLevels)
              [
                level.name,
                _amountFormat.format(level.stock),
                _amountFormat.format(level.averageCost),
                _amountFormat.format(level.stockValue),
              ],
          ],
          headerStyle: headerStyle,
          headerDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1, color: PdfColors.grey400)),
          ),
          cellAlignments: const {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        ),
        pw.Divider(),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('Total stock value', style: headerStyle),
            pw.SizedBox(width: 6),
            pw.Text(_amountFormat.format(totalStockValue), style: headerStyle),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('Stock movement', style: headerStyle),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const ['Movement type', 'Net quantity'],
          data: [
            for (final (type, quantity) in _movementRows(report))
              [type, _amountFormat.format(quantity)],
          ],
          headerStyle: headerStyle,
          headerDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1, color: PdfColors.grey400)),
          ),
          cellAlignments: const {1: pw.Alignment.centerRight},
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        ),
      ],
    ),
  );

  return document.save();
}

void downloadInventoryReportCsv(InventoryReport report, DateRange range) {
  triggerBrowserDownload(
    encodeCsvForExcel(buildInventoryReportCsv(report, range)),
    'inventory_report_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.csv',
    mimeType: 'text/csv',
  );
}

Future<void> downloadInventoryReportPdf(InventoryReport report, DateRange range) async {
  final bytes = await buildInventoryReportPdf(report, range, format: PdfPageFormat.a4);
  triggerBrowserDownload(
    bytes,
    'inventory_report_${DateFormat('yyyyMMdd').format(range.start)}-${DateFormat('yyyyMMdd').format(range.end)}.pdf',
    mimeType: 'application/pdf',
  );
}
