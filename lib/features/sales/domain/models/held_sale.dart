import 'package:duka_pos/features/sales/domain/models/cart_line.dart';

/// A sale parked mid-checkout so the cashier can serve another customer and
/// come back to it. Deliberately in-memory only (via [heldSalesProvider]) —
/// a held sale surviving a browser refresh is a reasonable future
/// enhancement, not a requirement today. [customerName] is a display
/// snapshot only (the resume list needs it without re-joining customers).
class HeldSale {
  const HeldSale({
    required this.id,
    required this.heldAt,
    required this.cart,
    required this.customerId,
    required this.customerName,
    required this.paymentMethod,
    required this.discount,
    required this.amountPaid,
  });

  final int id;
  final DateTime heldAt;
  final List<CartLine> cart;
  final int? customerId;
  final String? customerName;
  final String paymentMethod;
  final double discount;
  final double amountPaid;

  double get subtotal => cart.fold<double>(0, (sum, line) => sum + line.lineTotal);

  double get itemCount => cart.fold<double>(0, (sum, line) => sum + line.quantity);
}
