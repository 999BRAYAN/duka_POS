import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/users/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final usersStreamProvider = StreamProvider<List<User>>((ref) {
  return ref.watch(userRepositoryProvider).watchUsers();
});
