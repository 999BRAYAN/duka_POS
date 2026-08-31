import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'authorization_service.dart';
import 'current_user_provider.dart';

final authorizationServiceProvider = Provider<AuthorizationService>((ref) {
  return AuthorizationService(ref.watch(currentUserProvider));
});
