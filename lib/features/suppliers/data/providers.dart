import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/suppliers/data/repositories/supplier_repository_impl.dart';
import 'package:duka_pos/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final supplierRepositoryProvider = Provider<SupplierRepository>((ref) {
  return SupplierRepositoryImpl(ref.watch(databaseProvider));
});
