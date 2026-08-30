import 'package:drift/drift.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/domain/repositories/category_repository.dart';
import 'package:uuid/uuid.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._db);

  final DukaDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<Category> addCategory({required String name, String? description}) {
    return _db.into(_db.categories).insertReturning(
      CategoriesCompanion.insert(
        uuid: _uuid.v4(),
        name: name,
        description: Value(description),
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updateCategory(Category category) {
    return _db
        .update(_db.categories)
        .replace(category.copyWith(updatedAt: Value(DateTime.now())));
  }

  @override
  Future<void> deleteCategory(String uuid) {
    return (_db.delete(
      _db.categories,
    )..where((t) => t.uuid.equals(uuid))).go();
  }

  @override
  Future<Category?> getCategoryByUuid(String uuid) {
    return (_db.select(
      _db.categories,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  @override
  Stream<List<Category>> watchCategories() {
    return (_db.select(_db.categories)..orderBy([
      (t) => OrderingTerm(expression: t.name),
    ])).watch();
  }
}
