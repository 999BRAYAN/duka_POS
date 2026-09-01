import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/credit/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

const _paymentMethods = {'cash': 'Cash', 'mpesa': 'M-Pesa', 'card': 'Card'};

/// Records a payment against one customer's outstanding balance.
class ReceivePaymentScreen extends ConsumerStatefulWidget {
  const ReceivePaymentScreen({super.key, required this.customer});

  final Customer customer;

  @override
  ConsumerState<ReceivePaymentScreen> createState() => _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState extends ConsumerState<ReceivePaymentScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _method = 'cash';
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(creditServiceProvider).recordPayment(
        customerId: widget.customer.id,
        amount: amount,
        method: _method,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment of ${_amountFormat.format(amount)} recorded.')),
      );
      Navigator.of(context).pop();
    } on UnauthorizedException {
      setState(() => _error = "You don't have permission to record a payment.");
    } catch (e) {
      setState(() => _error = 'Could not record this payment: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive payment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.customer.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Current balance: ${_amountFormat.format(widget.customer.currentBalance)}',
                  style: TextStyle(color: AppColors.stone500),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: [
                    for (final entry in _paymentMethods.entries)
                      DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (value) => setState(() => _method = value ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.rust700)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Record payment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
