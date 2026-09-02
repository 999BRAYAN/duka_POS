import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/purchases/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

/// Records a payment against a purchase already on credit ('unpaid' or
/// 'partial'), the only way to move it toward 'paid' after stock has come
/// in — receiving stock only sets the payment status once, at the moment
/// goods arrive.
Future<void> showRecordPurchasePaymentDialog(
  BuildContext context, {
  required Purchase purchase,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _RecordPurchasePaymentDialog(purchase: purchase),
  );
}

class _RecordPurchasePaymentDialog extends ConsumerStatefulWidget {
  const _RecordPurchasePaymentDialog({required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<_RecordPurchasePaymentDialog> createState() =>
      _RecordPurchasePaymentDialogState();
}

class _RecordPurchasePaymentDialogState
    extends ConsumerState<_RecordPurchasePaymentDialog> {
  late final TextEditingController _amount;
  String? _error;
  bool _submitting = false;

  double get _outstanding => widget.purchase.total - widget.purchase.amountPaid;

  @override
  void initState() {
    super.initState();
    // Defaults to paying it off in full — the common case — while staying
    // editable for a partial top-up.
    _amount = TextEditingController(text: _amountFormat.format(_outstanding));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (amount > _outstanding) {
      setState(
        () => _error =
            'Only ${_amountFormat.format(_outstanding)} is owed on this purchase.',
      );
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await ref
          .read(purchaseServiceProvider)
          .recordPayment(widget.purchase.uuid, amount: amount);
      if (!mounted) return;
      // See product_form_screen.dart's _submit for why this unfocus matters.
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop();
    } on UnauthorizedException {
      setState(() => _error = "You don't have permission to record this payment.");
    } catch (e) {
      setState(() => _error = 'Could not record this payment: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Record payment — ${widget.purchase.referenceNumber ?? "purchase"}',
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_amountFormat.format(_outstanding)} owed of '
              '${_amountFormat.format(widget.purchase.total)} total.',
              style: TextStyle(fontSize: 12, color: SemanticColors.muted(context)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount paid'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.rust700)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record payment'),
        ),
      ],
    );
  }
}
