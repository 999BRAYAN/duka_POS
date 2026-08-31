import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/suppliers/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final suppliersStreamProvider = StreamProvider<List<Supplier>>((ref) {
  return ref.watch(supplierRepositoryProvider).watchSuppliers();
});
