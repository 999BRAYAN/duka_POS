import 'package:duka_pos/core/authorization/auth_service.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/users/domain/exceptions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown once, on a shop with no accounts at all: creates the manager and
/// signs them straight in. This replaced the dev-user seed that used to boot
/// everyone in as a hardcoded manager.
class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  ConsumerState<FirstRunSetupScreen> createState() => _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  final _fullName = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _fullName.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    if (_fullName.text.trim().isEmpty || _username.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name and a username.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = "Those passwords don't match.");
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final user = await auth.createFirstManager(
        username: _username.text,
        password: _password.text,
        fullName: _fullName.text,
      );
      if (!mounted) return;
      ref.invalidate(isSetUpProvider);
      ref.read(currentUserProvider.notifier).state = user;
    } on WeakPasswordException catch (e) {
      if (mounted) setState(() => _error = 'Password too short. $e');
    } on ManagerAlreadyExistsForSetupException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } on ManagerAlreadyExistsException {
      if (mounted) setState(() => _error = 'This shop already has a manager account.');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not create the account: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set up this till',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Create the manager account. It's the only account that can "
                      'add products, see reports and create staff logins.',
                      style: TextStyle(color: AppColors.stone500),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _fullName,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
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
                            'At least ${AuthService.minimumPasswordLength} characters',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Confirm password'),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.amber50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.amber200),
                      ),
                      child: Text(
                        'Write this password down somewhere safe. There is no way to '
                        'recover it — the shop data lives only on this device.',
                        style: TextStyle(fontSize: 12, color: AppColors.amber800),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: AppColors.rust700)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(_submitting ? 'Creating…' : 'Create account'),
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
