import 'package:duka_pos/features/users/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';
import 'authorization_service.dart';
import 'current_user_provider.dart';

final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  return AuthorizationService(ref.watch(currentUserProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(userRepositoryProvider));
});

/// Whether this shop has a manager account yet. False only on a brand-new
/// install, which is what routes the app to first-run setup rather than the
/// login screen.
final isSetUpProvider = FutureProvider<bool>((ref) {
  return ref.watch(authServiceProvider).isSetUp();
});
