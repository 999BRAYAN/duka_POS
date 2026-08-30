import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/users/data/repositories/user_repository_impl.dart';
import 'package:duka_pos/features/users/domain/repositories/user_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepositoryImpl(ref.watch(databaseProvider));
});
