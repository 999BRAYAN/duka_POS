import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/credit/domain/repositories/credit_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepositoryImpl(ref.watch(databaseProvider));
});
