import 'package:flutter/material.dart';

/// Shown once a sale has actually gone through — order processed, payment
/// taken — so "Print receipt" is a real button on a confirmation someone
/// has to act on, not a tag riding along the bottom of the screen on a
/// snackbar that times out before anyone reaches for it.
///
/// Stays open across a print: a cashier might print, then still want to
/// confirm before moving on, or reprint if the first copy jammed. Only
/// "Done" closes it.
Future<void> showSaleConfirmationDialog(
  BuildContext context, {
  required String invoiceNumber,
  required String total,
  required Future<void> Function() onPrintReceipt,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SaleConfirmationDialog(
      invoiceNumber: invoiceNumber,
      total: total,
      onPrintReceipt: onPrintReceipt,
    ),
  );
}

class _SaleConfirmationDialog extends StatefulWidget {
  const _SaleConfirmationDialog({
    required this.invoiceNumber,
    required this.total,
    required this.onPrintReceipt,
  });

  final String invoiceNumber;
  final String total;
  final Future<void> Function() onPrintReceipt;

  @override
  State<_SaleConfirmationDialog> createState() => _SaleConfirmationDialogState();
}

class _SaleConfirmationDialogState extends State<_SaleConfirmationDialog> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      // A direct click is a fresh user gesture, unlike calling
      // Printing.layoutPdf straight after an awaited save — some browsers
      // refuse a print dialog that isn't a synchronous continuation of a
      // click. This button press is that gesture.
      await widget.onPrintReceipt();
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.check_circle, color: Colors.green, size: 32),
      title: const Text('Sale complete'),
      content: Text(
        'Invoice ${widget.invoiceNumber} · ${widget.total}',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton.icon(
          onPressed: _printing ? null : _print,
          icon: _printing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print receipt'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
