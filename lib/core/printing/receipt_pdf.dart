import 'dart:typed_data';

import 'package:duka_pos/core/database/database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// No settings/business-profile feature exists yet to make this
// configurable — hardcoded until one does.
const _businessName = 'Duka POS';

const _paymentMethodLabels = {'cash': 'Cash', 'mpesa': 'M-Pesa', 'card': 'Card', 'credit': 'Credit'};

final _amountFormat = NumberFormat('#,##0.00');
final _dateFormat = DateFormat('d MMM yyyy, HH:mm');

/// Opens the platform's print flow for [sale]'s receipt — on web this is
/// the browser's native print dialog (with "Save as PDF" as one of its
/// destinations), the correct web equivalent of a mobile print sheet.
/// [onLayout] rebuilds the document per [Printing.layoutPdf]'s contract:
/// it may be called more than once if the user changes paper size/
/// orientation in that dialog, so [buildReceiptPdf] must stay a pure
/// function of its inputs plus whatever [PdfPageFormat] it's asked for.
Future<void> printReceipt({
  required Sale sale,
  required List<SaleItem> items,
  required Map<int, Product> productsById,
  User? cashier,
  Customer? customer,
}) {
  return Printing.layoutPdf(
    name: '${sale.invoiceNumber}.pdf',
    onLayout: (format) => buildReceiptPdf(
      sale: sale,
      items: items,
      productsById: productsById,
      cashier: cashier,
      customer: customer,
      format: format,
    ),
  );
}

/// Builds the receipt as PDF bytes. Kept separate from [printReceipt] so
/// tests can check its content directly without going through a real
/// print dialog.
Future<Uint8List> buildReceiptPdf({
  required Sale sale,
  required List<SaleItem> items,
  required Map<int, Product> productsById,
  User? cashier,
  Customer? customer,
  required PdfPageFormat format,
}) async {
  final document = pw.Document();
  final balanceDue = sale.total - sale.amountPaid;

  document.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                _businessName,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Receipt: ${sale.invoiceNumber}'),
            pw.Text('Date: ${_dateFormat.format(sale.createdAt)}'),
            pw.Text('Cashier: ${cashier?.fullName ?? 'Unknown'}'),
            pw.Text('Customer: ${customer?.name ?? 'Walk-in customer'}'),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Item', 'Qty', 'Price', 'Total'],
              data: [
                for (final item in items)
                  [
                    productsById[item.productId]?.name ?? 'Unknown product',
                    _amountFormat.format(item.quantity),
                    _amountFormat.format(item.unitPrice),
                    _amountFormat.format(item.total),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellAlignments: const {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              border: null,
              cellPadding: const pw.EdgeInsets.symmetric(vertical: 4),
            ),
            pw.Divider(),
            _totalsRow('Subtotal', sale.subtotal),
            if (sale.discount > 0) _totalsRow('Discount', -sale.discount),
            if (sale.tax > 0) _totalsRow('Tax', sale.tax),
            _totalsRow('Total', sale.total, bold: true),
            pw.SizedBox(height: 12),
            pw.Text(
              'Payment method: ${_paymentMethodLabels[sale.paymentMethod] ?? sale.paymentMethod}',
            ),
            _totalsRow('Amount paid', sale.amountPaid),
            if (balanceDue > 0) _totalsRow('Balance due', balanceDue, bold: true),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text('Thank you for your business!', style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        );
      },
    ),
  );

  return document.save();
}

pw.Widget _totalsRow(String label, double value, {bool bold = false}) {
  final style = pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: style),
        pw.Text(_amountFormat.format(value), style: style),
      ],
    ),
  );
}
