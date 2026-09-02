import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds a titled table as PDF bytes — the shared shape behind every
/// report/list export (a product breakdown, stock levels, sale history): a
/// title, a one-line subtitle (usually the period covered), a header row,
/// data rows, and an optional totals row below a divider. [pw.MultiPage]
/// rather than receipt_pdf.dart's single [pw.Page]: unlike a receipt, a
/// report's row count isn't bounded, so this paginates automatically
/// instead of clipping.
Future<Uint8List> buildTablePdf({
  required String title,
  required String subtitle,
  required List<String> headers,
  required List<List<String>> rows,
  List<String>? totalsRow,
  required PdfPageFormat format,
}) async {
  final document = pw.Document();

  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      build: (context) => [
        pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1, color: PdfColors.grey400)),
          ),
          cellAlignments: {
            for (var i = 1; i < headers.length; i++) i: pw.Alignment.centerRight,
          },
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        ),
        if (totalsRow != null) ...[
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              for (final cell in totalsRow)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6),
                  child: pw.Text(cell, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ),
            ],
          ),
        ],
      ],
    ),
  );

  return document.save();
}

/// One line of a [buildStatementPdf] — a label/value pair, [emphasize] for
/// a subtotal or the bottom line, matching the weight ReportsScreen's own
/// `_PnlRow` gives the same distinction on screen.
class StatementLine {
  const StatementLine(this.label, this.value, {this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;
}

/// Builds a label/value statement as PDF bytes — the profit & loss report's
/// shape, which is a handful of named figures rather than a table of rows.
Future<Uint8List> buildStatementPdf({
  required String title,
  required String subtitle,
  required List<StatementLine> lines,
  required PdfPageFormat format,
}) async {
  final document = pw.Document();

  document.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.SizedBox(height: 16),
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    line.label,
                    style: pw.TextStyle(
                      fontWeight: line.emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                  ),
                  pw.Text(
                    line.value,
                    style: pw.TextStyle(
                      fontWeight: line.emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  return document.save();
}
