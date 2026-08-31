import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_valuation_repository_impl.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_valuation_repository.dart';
import 'package:duka_pos/features/inventory/domain/services/inventory_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stockMovementRepositoryProvider = Provider<StockMovementRepository>((
  ref,
) {
  return StockMovementRepositoryImpl(ref.watch(databaseProvider));
});

final stockValuationRepositoryProvider = Provider<StockValuationRepository>((
  ref,
) {
  return StockValuationRepositoryImpl(ref.watch(databaseProvider));
});

final inventoryServiceProvider = Provider<InventoryService>((ref) {
  return InventoryService(
    ref.watch(stockMovementRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
