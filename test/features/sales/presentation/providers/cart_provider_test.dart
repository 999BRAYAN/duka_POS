import 'package:duka_pos/features/sales/domain/models/cart_line.dart';
import 'package:duka_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('cart starts empty', () {
    expect(container.read(cartProvider), isEmpty);
  });

  test('addProduct adds a new line', () {
    container.read(cartProvider.notifier).addProduct(
      productId: 1,
      name: 'Soda',
      price: 70,
      quantity: 2,
    );

    expect(container.read(cartProvider), [
      const CartLine(productId: 1, name: 'Soda', price: 70, quantity: 2),
    ]);
  });

  test('addProduct on an existing productId increases its quantity instead of duplicating', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 2);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 3);

    expect(container.read(cartProvider), [
      const CartLine(productId: 1, name: 'Soda', price: 70, quantity: 5),
    ]);
  });

  test('addProduct defaults quantity to 1', () {
    container.read(cartProvider.notifier).addProduct(productId: 1, name: 'Soda', price: 70);

    expect(container.read(cartProvider).single.quantity, 1);
  });

  test('adding the same product again combines quantity but keeps the original snapshotted price', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 1);
    notifier.addProduct(productId: 1, name: 'Soda', price: 999, quantity: 1);

    final line = container.read(cartProvider).single;
    expect(line.price, 70); // first snapshot wins, not the second call's price
    expect(line.quantity, 2);
  });

  test('setQuantity updates an existing line', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 2);
    notifier.setQuantity(1, 5);

    expect(container.read(cartProvider).single.quantity, 5);
  });

  test('setQuantity to zero or below removes the line', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 2);
    notifier.setQuantity(1, 0);

    expect(container.read(cartProvider), isEmpty);
  });

  test('removeLine drops only the matching product', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 1);
    notifier.addProduct(productId: 2, name: 'Chips', price: 60, quantity: 1);
    notifier.removeLine(1);

    expect(container.read(cartProvider).map((l) => l.productId), [2]);
  });

  test('clear empties the cart', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 1);
    notifier.clear();

    expect(container.read(cartProvider), isEmpty);
  });

  test('cartSubtotalProvider sums price times quantity across lines', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 2); // 140
    notifier.addProduct(productId: 2, name: 'Chips', price: 60, quantity: 3); // 180

    expect(container.read(cartSubtotalProvider), 320);
  });

  test('cartItemCountProvider sums quantities, not distinct lines', () {
    final notifier = container.read(cartProvider.notifier);
    notifier.addProduct(productId: 1, name: 'Soda', price: 70, quantity: 2);
    notifier.addProduct(productId: 2, name: 'Chips', price: 60, quantity: 3);

    expect(container.read(cartItemCountProvider), 5);
  });
}
