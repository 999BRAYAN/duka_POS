import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/purchases/data/providers.dart';
import 'package:duka_pos/features/suppliers/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final purchaseSearchQueryProvider = StateProvider<String>((ref) => '');

/// null means "all payment statuses". Values match Purchases.paymentStatus:
/// 'paid', 'partial', 'unpaid'.
final purchasePaymentStatusFilterProvider = StateProvider<String?>((ref) => null);

final purchasesStreamProvider = StreamProvider<List<Purchase>>((ref) {
  return ref.watch(purchaseRepositoryProvider).watchPurchases();
});

/// [purchasesStreamProvider] filtered by search text (matches PO reference
/// or supplier name) and payment status — recombined client-side, same
/// reasoning as filteredProductsProvider.
final filteredPurchasesProvider = Provider<AsyncValue<List<Purchase>>>((ref) {
  final purchasesAsync = ref.watch(purchasesStreamProvider);
  final suppliersAsync = ref.watch(suppliersStreamProvider);
  final query = ref.watch(purchaseSearchQueryProvider).trim().toLowerCase();
  final statusFilter = ref.watch(purchasePaymentStatusFilterProvider);

  return purchasesAsync.whenData((purchases) {
    final supplierNameById = {
      for (final s in suppliersAsync.valueOrNull ?? const <Supplier>[])
        s.id: s.name,
    };

    return purchases.where((purchase) {
      if (statusFilter != null && purchase.paymentStatus != statusFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = [
          purchase.referenceNumber ?? '',
          supplierNameById[purchase.supplierId] ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(query)) return false;
      }
      return true;
    }).toList();
  });
});
