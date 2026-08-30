import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:uuid/uuid.dart';

class SupplierRepositoryImpl implements SupplierRepository {
  SupplierRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Supplier> addSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
  }) {
    return _db.into(_db.suppliers).insertReturning(
      SuppliersCompanion.insert(
        uuid: _uuid.v4(),
        name: name,
        phone: Value(phone),
        email: Value(email),
        address: Value(address),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateSupplier(Supplier supplier) {
    return _db
        .update(_db.suppliers)
        .replace(supplier.copyWith(updatedAt: Value(DateTime.now())));
  }

  @override
  Future<void> deleteSupplier(String uuid) {
    return (_db.delete(
      _db.suppliers,
    )..where((t) => t.uuid.equals(uuid))).go();
  }

  @override
  Future<Supplier?> getSupplierByUuid(String uuid) {
    return (_db.select(
      _db.suppliers,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Stream<List<Supplier>> watchSuppliers() {
    return (_db.select(_db.suppliers)..orderBy([
      (t) => OrderingTerm(expression: t.name),
    ])).watch();
  }
}
