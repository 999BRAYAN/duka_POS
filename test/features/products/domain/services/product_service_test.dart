import 'package:drift/native.dart';
import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/authorization_service.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/products/data/repositories/product_repository_impl.dart';
import 'package:duka_pos/features/products/domain/exceptions.dart';
import 'package:duka_pos/features/products/domain/services/product_service.dart';
import 'package:flutter_test/flutter_test.dart';

User _userWithRole(String role) {
  return User(
    id: 1,
    uuid: 'u1',
    username: 'jdoe',
    passwordHash: 'hash',
    fullName: 'Jane Doe',
    role: role,
    isActive: true,
    createdAt: DateTime(2026),
  );
}

void main() {
  late DukaDatabase db;
  late ProductRepositoryImpl repository;

  setUp(() {
    db = DukaDatabase.forTesting(NativeDatabase.memory(setup: enableForeignKeys));
    repository = ProductRepositoryImpl(db);
  });

  tearDown(() => db.close());

  ProductService serviceAs(String role) {
    return ProductService(repository, AuthorizationService(_userWithRole(role)));
  }

  group('authorization', () {
    test('cashier cannot addProduct', () {
      expect(
        () => serviceAs('cashier').addProduct(
          name: 'Soda',
          costPrice: 50,
          sellingPrice: 80,
          minSellingPrice: 60,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('cashier cannot deactivateProduct', () {
      expect(
        () => serviceAs('cashier').deactivateProduct('some-uuid'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('manager can addProduct', () async {
      final product = await serviceAs('manager').addProduct(
        name: 'Soda',
        costPrice: 50,
        sellingPrice: 80,
        minSellingPrice: 60,
      );
      expect(product.name, 'Soda');
    });
  });

  group('price validation', () {
    test('minSellingPrice below costPrice is rejected without confirmation', () {
      expect(
        () => serviceAs('manager').addProduct(
          name: 'Soda',
          costPrice: 50,
          sellingPrice: 80,
          minSellingPrice: 40,
        ),
        throwsA(isA<PriceBelowCostException>()),
      );
    });

    test('minSellingPrice below costPrice succeeds with confirmPriceBelowCost', () async {
      final product = await serviceAs('manager').addProduct(
        name: 'Soda',
        costPrice: 50,
        sellingPrice: 80,
        minSellingPrice: 40,
        confirmPriceBelowCost: true,
      );
      expect(product.minSellingPrice, 40);
    });

    test('minSellingPrice equal to costPrice is allowed without confirmation', () async {
      final product = await serviceAs('manager').addProduct(
        name: 'Soda',
        costPrice: 50,
        sellingPrice: 80,
        minSellingPrice: 50,
      );
      expect(product.minSellingPrice, 50);
    });

    test('updateProduct enforces the same rule', () async {
      final product = await serviceAs('manager').addProduct(
        name: 'Soda',
        costPrice: 50,
        sellingPrice: 80,
        minSellingPrice: 60,
      );

      expect(
        () => serviceAs('manager').updateProduct(product.copyWith(minSellingPrice: 30)),
        throwsA(isA<PriceBelowCostException>()),
      );

      await serviceAs('manager').updateProduct(
        product.copyWith(minSellingPrice: 30),
        confirmPriceBelowCost: true,
      );
      final reloaded = await repository.getProductByUuid(product.uuid);
      expect(reloaded?.minSellingPrice, 30);
    });

    test('authorization is checked before price validation', () {
      // A cashier trying to save a below-cost price should see the
      // permission error, not the price error — auth is the outer gate.
      expect(
        () => serviceAs('cashier').addProduct(
          name: 'Soda',
          costPrice: 50,
          sellingPrice: 80,
          minSellingPrice: 40,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });
  });

  test('watchProducts requires no permission', () async {
    await serviceAs('manager').addProduct(
      name: 'Soda',
      costPrice: 50,
      sellingPrice: 80,
      minSellingPrice: 60,
    );
    final products = await serviceAs('cashier').watchProducts().first;
    expect(products.map((p) => p.name), ['Soda']);
  });

  test('deactivateProduct soft-deletes via the repository', () async {
    final product = await serviceAs('manager').addProduct(
      name: 'Soda',
      costPrice: 50,
      sellingPrice: 80,
      minSellingPrice: 60,
    );

    await serviceAs('manager').deactivateProduct(product.uuid);

    final reloaded = await repository.getProductByUuid(product.uuid);
    expect(reloaded?.isActive, isFalse);
  });
}
