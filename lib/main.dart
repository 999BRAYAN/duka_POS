import 'dart:async';

import 'package:duka_pos/core/authorization/presentation/auth_gate.dart';
import 'package:duka_pos/core/storage/persistent_storage.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/core/theme/theme_mode_provider.dart';
import 'package:duka_pos/features/customers/data/walk_in_customer_seed.dart';
import 'package:duka_pos/features/products/presentation/screens/product_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(requestPersistentStorage());

  final container = ProviderContainer();
  await seedWalkInCustomer(container);

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Duka POS',
      theme: buildAppTheme(),
      darkTheme: buildAppDarkTheme(),
      themeMode: ref.watch(themeModeProvider),
      // Nothing in the app is reachable until someone signs in — the gate
      // wraps the whole app rather than each screen redirecting for itself.
      home: const AuthGate(child: ProductListScreen()),
    );
  }
}
