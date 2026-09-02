import 'package:duka_pos/core/authorization/auth_service.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/features/users/domain/exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Creates a staff login. Cashier is the default and the common case; the
/// manager role is offered only because the schema allows exactly one and a
/// shop may need to hand over.
class UserFormScreen extends ConsumerStatefulWidget {
  const UserFormScreen({super.key});

  @override
  ConsumerState<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends ConsumerState<UserFormScreen> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String _role = 'cashier';
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_fullName.text.trim().isEmpty || _username.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name and a username.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      ref.read(authorizationServiceProvider).require(Permission.manageStaff);
      await ref.read(authServiceProvider).createUser(
        username: _username.text,
        password: _password.text,
        fullName: _fullName.text,
        role: _role,
      );
      // See product_form_screen.dart's _submit for why this unfocus matters.
      FocusManager.instance.primaryFocus?.unfocus();
      if (mounted) Navigator.of(context).pop();
    } on UnauthorizedException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } on WeakPasswordException catch (e) {
      if (mounted) setState(() => _error = 'Password too short. $e');
    } on ManagerAlreadyExistsException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the login: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add staff login')),
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
                      controller: _fullName,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText:
                            'At least ${AuthService.minimumPasswordLength} characters. '
                            'They can change it after signing in.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'cashier',
                          child: Text('Cashier — can only ring up sales'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('Manager — full access'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _role = value ?? 'cashier'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Text(_submitting ? 'Creating…' : 'Create login'),
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
