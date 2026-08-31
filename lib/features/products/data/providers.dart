import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/products/data/repositories/category_repository_impl.dart';
import 'package:duka_pos/features/products/data/repositories/product_repository_impl.dart';
import 'package:duka_pos/features/products/domain/repositories/category_repository.dart';
import 'package:duka_pos/features/products/domain/repositories/product_repository.dart';
import 'package:duka_pos/features/products/domain/services/product_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepositoryImpl(ref.watch(databaseProvider));
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepositoryImpl(ref.watch(databaseProvider));
});

final productServiceProvider = Provider<ProductService>((ref) {
  return ProductService(
    ref.watch(productRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
