import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/presentation/change_password_dialog.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/users/data/providers.dart';
import 'package:duka_pos/features/users/presentation/providers.dart';
import 'package:duka_pos/features/users/presentation/screens/user_form_screen.dart';
import 'package:duka_pos/core/navigation/app_drawer.dart';
import 'package:duka_pos/core/navigation/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Staff logins: who can sign in, and what they may do. Manager-only.
class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersStreamProvider);
    final signedIn = ref.watch(currentUserProvider);
    final canManage = ref.watch(authorizationServiceProvider).can(Permission.manageStaff);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff logins'),
        actions: [
          if (canManage)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UserFormScreen()),
                ),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Add staff'),
              ),
            ),
        ],
      ),
      drawer: NavRail.isPersistent(context) ? null : const AppDrawer(current: 'staff'),
      body: NavRail(destination: 'staff', child: !canManage
          ? const Center(child: Text('Only a manager can manage staff logins.'))
          : usersAsync.when(
              data: (users) => _table(context, ref, users, signedIn),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Could not load staff: $error')),
            ),
    ));
  }

  Widget _table(BuildContext context, WidgetRef ref, List<User> users, User? signedIn) {
    if (users.isEmpty) {
      return const Center(child: Text('No staff logins yet.'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Username')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('')),
          ],
          rows: [
            for (final user in users)
              DataRow(
                color: user.isActive
                    ? null
                    : WidgetStatePropertyAll(AppColors.stone100),
                cells: [
                  DataCell(Text(user.fullName)),
                  DataCell(Text(user.username)),
                  DataCell(Text(user.role)),
                  DataCell(
                    user.isActive
                        ? const Text('Active')
                        : Text('Disabled', style: TextStyle(color: AppColors.stone500)),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () =>
                              showChangePasswordDialog(context, ref, user: user),
                          child: const Text('Reset password'),
                        ),
                        // Signing yourself out of your own shop by
                        // disabling your own account would leave nobody
                        // able to sign in — the manager role is unique, so
                        // there is no second manager to undo it.
                        if (user.isActive && user.id != signedIn?.id)
                          TextButton(
                            onPressed: () => _deactivate(context, ref, user),
                            child: Text(
                              'Disable',
                              style: TextStyle(color: AppColors.rust700),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, WidgetRef ref, User user) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Disable ${user.fullName}?'),
        content: const Text(
          'They will no longer be able to sign in. Their past sales stay on record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      ref.read(authorizationServiceProvider).require(Permission.manageStaff);
      await ref.read(userRepositoryProvider).deactivateUser(user.uuid);
    } on UnauthorizedException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not disable: $e')));
    }
  }
}
