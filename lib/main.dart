import 'dart:async';

import 'package:duka_pos/core/authorization/dev_user_seed.dart';
import 'package:duka_pos/core/storage/persistent_storage.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/products/presentation/screens/product_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(requestPersistentStorage());

  final container = ProviderContainer();
  await seedDevUser(container);

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Duka POS',
      theme: buildAppTheme(),
      home: const ProductListScreen(),
    );
  }
}
