import 'package:drift/drift.dart' show Value;
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/data/providers.dart';
import 'package:duka_pos/features/customers/domain/exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds a customer, or edits one when [customer] is given.
///
/// The walk-in row is refused by CustomerService.updateCustomer even for a
/// manager, so this form never opens for it — but the guard that matters
/// lives in the service, not here.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({this.customer, super.key});

  final Customer? customer;

  bool get isEditing => customer != null;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _creditLimitController;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.customer;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _addressController = TextEditingController(text: existing?.address ?? '');
    _creditLimitController = TextEditingController(
      text: existing == null ? '0' : _plain(existing.creditLimit),
    );
  }

  static String _plain(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    String? blankToNull(String value) => value.trim().isEmpty ? null : value.trim();

    try {
      final service = ref.read(customerServiceProvider);
      final existing = widget.customer;

      if (existing != null) {
        await service.updateCustomer(
          existing.copyWith(
            name: name,
            phone: Value(blankToNull(_phoneController.text)),
            email: Value(blankToNull(_emailController.text)),
            address: Value(blankToNull(_addressController.text)),
            creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await service.addCustomer(
          name: name,
          phone: blankToNull(_phoneController.text),
          email: blankToNull(_emailController.text),
          address: blankToNull(_addressController.text),
          creditLimit: double.tryParse(_creditLimitController.text) ?? 0,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isEditing ? '$name updated.' : '$name added.')),
      );
      Navigator.of(context).pop();
    } on UnauthorizedException catch (e) {
      setState(() => _error = '$e');
    } on WalkInCustomerNotEditableException catch (e) {
      setState(() => _error = '$e');
    } catch (e) {
      setState(() => _error = 'Could not save this customer: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit customer' : 'Add customer')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _creditLimitController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Credit limit',
                    helperText: 'How much unpaid balance this customer may carry.',
                  ),
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
                      : Text(widget.isEditing ? 'Save changes' : 'Add customer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
