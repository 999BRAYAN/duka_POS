import 'package:duka_pos/core/authorization/auth_service.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Sign-in. Reached whenever no one is signed in and the shop already has a
/// manager account; a fresh install gets [FirstRunSetupScreen] instead.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final user = await ref.read(authServiceProvider).signIn(
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      // Unfocus before the swap below: setting currentUserProvider replaces
      // this whole screen with the app's main tree in one rebuild, and
      // tearing down a still-focused TextField's Element that way trips a
      // Flutter framework assertion (InheritedElement._dependents not
      // empty) — see product_form_screen.dart's _submit for the full story.
      FocusManager.instance.primaryFocus?.unfocus();
      // Setting this is what dismisses the gate and shows the app.
      ref.read(currentUserProvider.notifier).state = user;
    } on InvalidCredentialsException catch (e) {
      if (mounted) setState(() => _error = '$e');
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not sign in: $e');
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
            constraints: const BoxConstraints(maxWidth: 380),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Duka POS',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in to open the till',
                      style: TextStyle(color: AppColors.stone500),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _username,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                      decoration: const InputDecoration(labelText: 'Password'),
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
                        child: Text(_submitting ? 'Signing in…' : 'Sign in'),
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
