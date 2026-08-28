import 'package:duka_pos/core/database/database.dart';

/// Contract for reading and writing [Category] rows.
abstract interface class CategoryRepository {
  Future<Category> addCategory({required String name, String? description});

  Future<void> updateCategory(Category category);

  Future<void> deleteCategory(String uuid);

  Future<Category?> getCategoryByUuid(String uuid);

  Stream<List<Category>> watchCategories();
}
