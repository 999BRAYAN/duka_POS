import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/presentation/change_password_dialog.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/users/presentation/screens/user_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who is signed in, and the things they can do about it: change their own
/// password, manage staff logins (managers only), sign out.
///
/// Replaced ActingAsBadge, which only displayed the dev-seeded user because
/// there was no sign-in to act on.
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final canManageStaff = ref
        .watch(authorizationServiceProvider)
        .can(Permission.manageStaff);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: PopupMenuButton<String>(
          tooltip: 'Account',
          position: PopupMenuPosition.under,
          onSelected: (value) async {
            switch (value) {
              case 'staff':
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserListScreen()),
                );
              case 'password':
                await showChangePasswordDialog(context, ref, user: user);
              case 'signout':
                ref.read(currentUserProvider.notifier).state = null;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                '${user.fullName} · ${user.role}',
                style: const TextStyle(fontSize: 12, color: AppColors.stone600),
              ),
            ),
            const PopupMenuDivider(),
            if (canManageStaff)
              const PopupMenuItem(value: 'staff', child: Text('Staff logins')),
            const PopupMenuItem(value: 'password', child: Text('Change my password')),
            const PopupMenuItem(value: 'signout', child: Text('Sign out')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.stone100,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.stone200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${user.fullName} · ${user.role}',
                  style: const TextStyle(fontSize: 12, color: AppColors.stone600),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.stone600),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
