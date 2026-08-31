import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/inventory/data/providers.dart';
import 'package:duka_pos/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:duka_pos/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:duka_pos/features/purchases/domain/services/purchase_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  return PurchaseRepositoryImpl(
    ref.watch(databaseProvider),
    ref.watch(stockMovementRepositoryProvider),
  );
});

final purchaseServiceProvider = Provider<PurchaseService>((ref) {
  return PurchaseService(
    ref.watch(purchaseRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
