import 'package:drift/drift.dart' show Value;
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/suppliers/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds a supplier, or edits one when [supplier] is given.
class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({this.supplier, super.key});

  final Supplier? supplier;

  bool get isEditing => supplier != null;

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _name = TextEditingController(text: s?.name ?? '');
    _phone = TextEditingController(text: s?.phone ?? '');
    _email = TextEditingController(text: s?.email ?? '');
    _address = TextEditingController(text: s?.address ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _orNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _submit() async {
    if (_submitting) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the supplier a name.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      ref.read(authorizationServiceProvider).require(Permission.manageProducts);
      final repository = ref.read(supplierRepositoryProvider);

      if (widget.isEditing) {
        await repository.updateSupplier(
          widget.supplier!.copyWith(
            name: _name.text.trim(),
            phone: Value(_orNull(_phone)),
            email: Value(_orNull(_email)),
            address: Value(_orNull(_address)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await repository.addSupplier(
          name: _name.text.trim(),
          phone: _orNull(_phone),
          email: _orNull(_email),
          address: _orNull(_address),
        );
      }
      // See product_form_screen.dart's _submit for why this unfocus matters.
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) Navigator.of(context).pop();
    } on UnauthorizedException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the supplier: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit supplier' : 'Add supplier'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Supplier name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone (optional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email (optional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _address,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Address (optional)'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.rust700)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(
                        _submitting
                            ? 'Saving…'
                            : widget.isEditing
                            ? 'Save changes'
                            : 'Add supplier',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
