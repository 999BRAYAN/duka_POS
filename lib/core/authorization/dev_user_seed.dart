import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/users/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'current_user_provider.dart';

// There's no login screen yet (auth's building blocks — authenticate/
// hasManager — exist but nothing calls them), so every write gated behind
// AuthorizationService would otherwise always be denied. Until that screen
// exists, boot into a real persisted manager user rather than a fake
// in-memory one — a fake id would violate the userId foreign key on
// Purchases/StockMovements the moment a gated action tries to write.
// Delete this file once real sign-in lands.
Future<void> seedDevUser(ProviderContainer container) async {
  final db = container.read(databaseProvider);
  var user = await (db.select(db.users)
        ..where((t) => t.isActive.equals(true))
        ..limit(1))
      .getSingleOrNull();

  user ??= await container.read(userRepositoryProvider).createUser(
    username: 'dev',
    passwordHash: 'dev',
    fullName: 'Dev Manager',
    role: 'manager',
  );

  container.read(currentUserProvider.notifier).state = user;
}
