import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/presentation/first_run_setup_screen.dart';
import 'package:duka_pos/core/authorization/presentation/sign_in_screen.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Decides what the app shows before anything else does: setup on a fresh
/// install, sign-in when signed out, otherwise [child].
///
/// This is the only thing standing between a visitor and the till, so it is
/// deliberately the outermost widget of the app rather than a redirect
/// individual screens perform for themselves.
class AuthGate extends ConsumerWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user != null) return child;

    return ref
        .watch(isSetUpProvider)
        .when(
          data: (isSetUp) => isSetUp ? const SignInScreen() : const FirstRunSetupScreen(),
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            body: Center(child: Text('Could not open the shop database: $error')),
          ),
        );
  }
}
