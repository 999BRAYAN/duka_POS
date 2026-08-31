import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/inventory/data/providers.dart';
import 'package:duka_pos/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:duka_pos/features/sales/domain/repositories/sale_repository.dart';
import 'package:duka_pos/features/sales/domain/services/sale_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(stockMovementRepositoryProvider),
  );
});

final saleServiceProvider = Provider<SaleService>((ref) {
  return SaleService(
    ref.watch(saleRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
