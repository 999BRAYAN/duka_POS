import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/presentation/change_password_dialog.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/core/theme/theme_mode_provider.dart';
import 'package:duka_pos/features/customers/presentation/screens/customer_list_screen.dart';
import 'package:duka_pos/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:duka_pos/features/expenses/presentation/screens/expenses_screen.dart';
import 'package:duka_pos/features/inventory/presentation/screens/stock_adjustment_screen.dart';
import 'package:duka_pos/features/products/presentation/screens/product_list_screen.dart';
import 'package:duka_pos/features/purchases/presentation/screens/purchase_list_screen.dart';
import 'package:duka_pos/features/reports/presentation/screens/reports_screen.dart';
import 'package:duka_pos/features/sales/presentation/screens/sale_screen.dart';
import 'package:duka_pos/features/sales/presentation/screens/sales_history_screen.dart';
import 'package:duka_pos/features/suppliers/presentation/screens/supplier_list_screen.dart';
import 'package:duka_pos/features/users/presentation/screens/user_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every screen in the app, in one place.
///
/// [permission] is what the destination needs; an item the signed-in user
/// can't reach is shown disabled rather than hidden, so a cashier can see
/// the shop has a Reports screen and knows to ask, instead of wondering
/// whether the software has one at all.
class _Destination {
  const _Destination(this.id, this.label, this.icon, this.permission, this.build);

  final String id;
  final String label;
  final IconData icon;
  final Permission? permission;
  final Widget Function() build;
}

class _Group {
  const _Group(this.label, this.destinations);
  final String label;
  final List<_Destination> destinations;
}

final _groups = <_Group>[
  _Group('Selling', [
    _Destination('sell', 'New sale', Icons.point_of_sale, Permission.processSale,
        () => const SaleScreen()),
    _Destination('sales', 'Sales history', Icons.receipt_long_outlined, null,
        () => const SalesHistoryScreen()),
  ]),
  _Group('Stock', [
    _Destination('products', 'Products', Icons.inventory_2_outlined, null,
        () => const ProductListScreen()),
    _Destination('adjust', 'Stock adjustments', Icons.tune, Permission.adjustStock,
        () => const StockAdjustmentScreen()),
    _Destination('purchases', 'Receive stock', Icons.local_shipping_outlined,
        Permission.receiveStock, () => const PurchaseListScreen()),
    _Destination('suppliers', 'Suppliers', Icons.store_outlined, Permission.manageProducts,
        () => const SupplierListScreen()),
  ]),
  _Group('People', [
    _Destination('customers', 'Customers', Icons.people_outline, null,
        () => const CustomerListScreen()),
    _Destination('staff', 'Staff logins', Icons.badge_outlined, Permission.manageStaff,
        () => const UserListScreen()),
  ]),
  _Group('Money', [
    _Destination('expenses', 'Expenses', Icons.payments_outlined, Permission.manageExpenses,
        () => const ExpensesScreen()),
    _Destination('dashboard', 'Dashboard', Icons.dashboard_outlined, Permission.manageProducts,
        () => const DashboardScreen()),
    _Destination('reports', 'Reports', Icons.bar_chart_outlined, Permission.manageProducts,
        () => const ReportsScreen()),
  ]),
];

/// The app's navigation. Opened from the hamburger every screen carries.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({required this.current, this.persistent = false, super.key});

  /// Which destination is showing, so it can be marked and re-tapping it
  /// just closes the drawer instead of pushing the same screen again.
  final String current;

  /// True when the drawer is part of the page rather than sliding over it —
  /// then tapping an entry must not try to pop a route that isn't there.
  final bool persistent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final authorization = ref.watch(authorizationServiceProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Drawer(
      elevation: persistent ? 0 : null,
      // Square edge when it is part of the page: a rounded corner only makes
      // sense on something that slid over the content.
      shape: persistent ? const RoundedRectangleBorder() : null,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.fullName ?? 'Duka POS',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (user != null)
                    Text(
                      user.role,
                      style: TextStyle(fontSize: 12, color: SemanticColors.muted(context)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final group in _groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Text(
                        group.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: SemanticColors.muted(context),
                        ),
                      ),
                    ),
                    for (final destination in group.destinations)
                      _item(context, ref, destination, authorization),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icons only: three labelled segments do not fit the rail's
                  // width, and these three icons are unambiguous.
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                        tooltip: 'Light',
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto_outlined, size: 18),
                        tooltip: 'Match the device',
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                        tooltip: 'Dark',
                      ),
                    ],
                    selected: {themeMode},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                    ),
                    onSelectionChanged: (selection) =>
                        ref.read(themeModeProvider.notifier).state = selection.first,
                  ),
                  const SizedBox(height: 8),
                  if (user != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.password_outlined, size: 20),
                      title: const Text('Change my password'),
                      onTap: () {
                        if (!persistent) Navigator.of(context).pop();
                        showChangePasswordDialog(context, ref, user: user);
                      },
                    ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.logout, size: 20),
                    title: const Text('Sign out'),
                    onTap: () {
                      if (!persistent) Navigator.of(context).pop();
                      ref.read(currentUserProvider.notifier).state = null;
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    WidgetRef ref,
    _Destination destination,
    dynamic authorization,
  ) {
    final allowed =
        destination.permission == null || authorization.can(destination.permission);
    final selected = destination.id == current;

    return ListTile(
      dense: true,
      selected: selected,
      enabled: allowed,
      leading: Icon(destination.icon, size: 20),
      title: Text(destination.label, overflow: TextOverflow.ellipsis),
      // A small lock rather than the word "manager": the longest labels plus
      // a word of explanation do not fit the rail's width, and the tooltip
      // carries the reason for anyone who wonders.
      trailing: allowed
          ? null
          : Tooltip(
              message: 'Only a manager can open this',
              child: Icon(
                Icons.lock_outline,
                size: 14,
                color: SemanticColors.muted(context),
              ),
            ),
      onTap: !allowed
          ? null
          : () {
              if (!persistent) Navigator.of(context).pop();
              if (selected) return;
              // Replace rather than push: the drawer is the navigation, so
              // the back stack should not fill with every screen visited.
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => destination.build()),
              );
            },
    );
  }
}
