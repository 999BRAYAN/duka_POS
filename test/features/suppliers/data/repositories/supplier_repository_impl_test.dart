import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/suppliers/data/repositories/supplier_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late SupplierRepositoryImpl repo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = SupplierRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('addSupplier then getSupplierByUuid round-trips', () async {
    final supplier = await repo.addSupplier(name: 'Acme Wholesale', phone: '0700000000');

    final found = await repo.getSupplierByUuid(supplier.uuid);
    expect(found?.name, 'Acme Wholesale');
    expect(found?.phone, '0700000000');
  });

  test('updateSupplier persists changes and sets updatedAt', () async {
    final supplier = await repo.addSupplier(name: 'Acme');
    await repo.updateSupplier(supplier.copyWith(name: 'Acme Renamed'));

    final found = await repo.getSupplierByUuid(supplier.uuid);
    expect(found?.name, 'Acme Renamed');
    expect(found?.updatedAt, isNotNull);
  });

  test('deleteSupplier removes the row', () async {
    final supplier = await repo.addSupplier(name: 'Acme');
    await repo.deleteSupplier(supplier.uuid);

    expect(await repo.getSupplierByUuid(supplier.uuid), isNull);
  });

  test('watchSuppliers emits alphabetically ordered rows', () async {
    await repo.addSupplier(name: 'Zeta');
    await repo.addSupplier(name: 'Alpha');

    final suppliers = await repo.watchSuppliers().first;
    expect(suppliers.map((s) => s.name), ['Alpha', 'Zeta']);
  });
}
