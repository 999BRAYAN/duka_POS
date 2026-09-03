import 'package:duka_pos/core/authorization/auth_service.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/users/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Switches the signed-in user without leaving the app: pick a profile,
/// enter that profile's password, and the till carries on as them.
///
/// Reuses [AuthService.signIn] — the same check a full sign-in performs —
/// and just reassigns [currentUserProvider] on success, exactly like
/// SignInScreen does. That's what avoids the sign-out/reload round trip:
/// nothing here tears the app down, so whatever screen was open stays open.
Future<void> showSwitchUserDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _SwitchUserDialog(),
  );
}

class _SwitchUserDialog extends ConsumerStatefulWidget {
  const _SwitchUserDialog();

  @override
  ConsumerState<_SwitchUserDialog> createState() => _SwitchUserDialogState();
}

class _SwitchUserDialogState extends ConsumerState<_SwitchUserDialog> {
  User? _target;
  final _password = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _pick(User user) {
    setState(() {
      _target = user;
      _error = null;
    });
  }

  void _back() {
    setState(() {
      _target = null;
      _password.clear();
      _error = null;
    });
  }

  Future<void> _submit() async {
    final target = _target;
    if (target == null || _submitting) return;

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final user = await ref
          .read(authServiceProvider)
          .signIn(username: target.username, password: _password.text);
      if (!mounted) return;
      // Same unfocus-before-swap reasoning as SignInScreen._submit — tearing
      // down a still-focused TextField's Element while it's a dependent
      // trips a framework assertion.
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(currentUserProvider.notifier).state = user;
      Navigator.of(context).pop();
    } on InvalidCredentialsException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not switch users: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) return _pickerDialog(context);

    return AlertDialog(
      title: Text('Sign in as ${target.fullName}'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _back,
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Signing in…' : 'Switch'),
        ),
      ],
    );
  }

  Widget _pickerDialog(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.id;
    final usersAsync = ref.watch(usersStreamProvider);

    return AlertDialog(
      title: const Text('Switch user'),
      content: SizedBox(
        width: 340,
        height: 320,
        child: usersAsync.when(
          data: (allUsers) {
            final users = allUsers
                .where((u) => u.isActive && u.id != currentUserId)
                .toList();
            if (users.isEmpty) {
              return Center(
                child: Text(
                  'No other staff accounts to switch to.',
                  style: TextStyle(color: SemanticColors.muted(context)),
                ),
              );
            }
            return ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                return ListTile(
                  title: Text(user.fullName),
                  subtitle: Text(user.role),
                  onTap: () => _pick(user),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Could not load staff: $error')),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
