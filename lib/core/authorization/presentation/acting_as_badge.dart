import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows who seedDevUser (see dev_user_seed.dart) signed in as — there's no
/// real sign-in UI yet, so this is the only visibility into which role's
/// permissions are in effect. Delete alongside dev_user_seed.dart once real
/// sign-in exists.
class ActingAsBadge extends ConsumerWidget {
  const ActingAsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.stone100,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.stone200),
          ),
          child: Text(
            '${user.fullName} · ${user.role}',
            style: const TextStyle(fontSize: 12, color: AppColors.stone600),
          ),
        ),
      ),
    );
  }
}
