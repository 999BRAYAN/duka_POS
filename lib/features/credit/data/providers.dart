import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/credit/data/repositories/credit_repository_impl.dart';
import 'package:duka_pos/features/credit/domain/repositories/credit_repository.dart';
import 'package:duka_pos/features/credit/domain/services/credit_service.dart';
import 'package:duka_pos/features/sales/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final creditRepositoryProvider = Provider<CreditRepository>((ref) {
  return CreditRepositoryImpl(ref.watch(databaseProvider));
});

// Depends on saleRepositoryProvider, not creditRepositoryProvider — see
// CreditService's class doc for why the direction matters.
final creditServiceProvider = Provider<CreditService>((ref) {
  return CreditService(
    ref.watch(saleRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
