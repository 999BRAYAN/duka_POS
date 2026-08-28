import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Supplier] rows.
abstract interface class SupplierRepository {
  Future<Supplier> addSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
  });

  Future<void> updateSupplier(Supplier supplier);

  Future<void> deleteSupplier(String uuid);

  Future<Supplier?> getSupplierByUuid(String uuid);

  Stream<List<Supplier>> watchSuppliers();
}
