import 'package:duka_pos/core/authorization/auth_service.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sets a new password for [user]. Used both for your own account and, from
/// the staff screen, for resetting a cashier's forgotten password — a
/// manager can reset without knowing the old one, which is the only way to
/// recover an account when nothing can email a reset link.
Future<void> showChangePasswordDialog(
  BuildContext context,
  WidgetRef ref, {
  required User user,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ChangePasswordDialog(user: user),
  );
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog({required this.user});

  final User user;

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = "Those passwords don't match.");
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      await ref
          .read(authServiceProvider)
          .changePassword(user: widget.user, newPassword: _password.text);
      if (mounted) Navigator.of(context).pop();
    } on WeakPasswordException catch (e) {
      if (mounted) setState(() => _error = 'Password too short. $e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not change the password: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New password for ${widget.user.fullName}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New password',
                helperText: 'At least ${AuthService.minimumPasswordLength} characters',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Confirm password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              )),
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
          child: const Text('Change password'),
        ),
      ],
    );
  }
}
