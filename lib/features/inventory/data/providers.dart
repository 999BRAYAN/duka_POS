import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/inventory/data/repositories/stock_movement_repository_impl.dart';
import 'package:duka_pos/features/inventory/domain/repositories/stock_movement_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stockMovementRepositoryProvider = Provider<StockMovementRepository>((
  ref,
) {
  return StockMovementRepositoryImpl(ref.watch(databaseProvider));
});
