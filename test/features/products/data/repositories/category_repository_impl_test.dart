import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/data/repositories/category_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DukaDatabase db;
  late CategoryRepositoryImpl repo;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repo = CategoryRepositoryImpl(db);
  });

  tearDown(() => db.close());

  test('addCategory then getCategoryByUuid round-trips', () async {
    final category = await repo.addCategory(name: 'Beverages', description: 'Drinks');

    final found = await repo.getCategoryByUuid(category.uuid);
    expect(found?.name, 'Beverages');
    expect(found?.description, 'Drinks');
  });

  test('deleteCategory removes the row', () async {
    final category = await repo.addCategory(name: 'Beverages');
    await repo.deleteCategory(category.uuid);

    expect(await repo.getCategoryByUuid(category.uuid), isNull);
  });

  test('deleteCategory referenced by a product throws', () async {
    final category = await repo.addCategory(name: 'Beverages');
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        uuid: 'p1',
        name: 'Soda',
        categoryId: Value(category.id),
        createdAt: DateTime.now(),
      ),
    );

    expect(() => repo.deleteCategory(category.uuid), throwsA(isA<Exception>()));
  });
}
