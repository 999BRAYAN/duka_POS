import 'dart:typed_data';

import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/export/csv.dart';
import 'package:duka_pos/core/printing/report_pdf.dart';
import 'package:duka_pos/core/web/browser_download.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

final _dateFormat = DateFormat('d MMM yyyy, HH:mm');
final _amountFormat = NumberFormat('#,##0.00');

String _customerName(Sale sale, Map<int, Customer> customerById) =>
    sale.customerId == null ? 'Walk-in' : customerById[sale.customerId]?.name ?? '—';

String _statusLabel(Sale sale) {
  if (sale.status == 'void') return 'Void';
  return sale.total - sale.amountPaid > 0 ? 'On account' : 'Paid';
}

/// Exports exactly the rows [SalesHistoryScreen] has on screen — whatever
/// [sales] the caller passes in, void sales included, in the same order.
/// There is no separate server-side query here: the screen already holds
/// the full, current list via its stream provider.
String buildSalesHistoryCsv(List<Sale> sales, Map<int, Customer> customerById) {
  return buildCsv(
    ['Receipt', 'Date', 'Customer', 'Total', 'Paid', 'Status'],
    [
      for (final sale in sales)
        [
          sale.invoiceNumber,
          _dateFormat.format(sale.createdAt),
          _customerName(sale, customerById),
          sale.total.toStringAsFixed(2),
          sale.amountPaid.toStringAsFixed(2),
          _statusLabel(sale),
        ],
    ],
  );
}

Future<Uint8List> buildSalesHistoryPdf(
  List<Sale> sales,
  Map<int, Customer> customerById, {
  required PdfPageFormat format,
}) {
  final totalRevenue = sales
      .where((s) => s.status != 'void')
      .fold<double>(0, (sum, s) => sum + s.total);

  return buildTablePdf(
    title: 'Sales history',
    subtitle: '${sales.length} sale(s)',
    headers: const ['Receipt', 'Date', 'Customer', 'Total', 'Paid', 'Status'],
    rows: [
      for (final sale in sales)
        [
          sale.invoiceNumber,
          _dateFormat.format(sale.createdAt),
          _customerName(sale, customerById),
          _amountFormat.format(sale.total),
          _amountFormat.format(sale.amountPaid),
          _statusLabel(sale),
        ],
    ],
    totalsRow: ['Total revenue (excl. void)', _amountFormat.format(totalRevenue)],
    format: format,
  );
}

void downloadSalesHistoryCsv(List<Sale> sales, Map<int, Customer> customerById) {
  triggerBrowserDownload(
    encodeCsvForExcel(buildSalesHistoryCsv(sales, customerById)),
    'sales_history_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv',
    mimeType: 'text/csv',
  );
}

Future<void> downloadSalesHistoryPdf(List<Sale> sales, Map<int, Customer> customerById) async {
  final bytes = await buildSalesHistoryPdf(sales, customerById, format: PdfPageFormat.a4);
  triggerBrowserDownload(
    bytes,
    'sales_history_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
    mimeType: 'application/pdf',
  );
}
