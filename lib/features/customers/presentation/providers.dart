import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/data/providers.dart';
import 'package:duka_pos/features/customers/domain/models/customer_ledger_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers();
});

final customerSearchQueryProvider = StateProvider<String>((ref) => '');

/// [customersStreamProvider] filtered by search text (matches name or
/// phone) — recombined client-side, same reasoning as
/// filteredProductsProvider/filteredPurchasesProvider.
final filteredCustomersProvider = Provider<AsyncValue<List<Customer>>>((ref) {
  final customersAsync = ref.watch(customersStreamProvider);
  final query = ref.watch(customerSearchQueryProvider).trim().toLowerCase();

  return customersAsync.whenData((customers) {
    if (query.isEmpty) return customers;
    return customers.where((customer) {
      final haystack = [customer.name, customer.phone ?? ''].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  });
});

/// One customer's statement (see CustomerLedgerRepository), fetched fresh
/// per screen visit — not a Stream, since combining two live queries
/// (Sales + CreditTransactions) into one running-balance list isn't
/// something this app's Riverpod setup does anywhere else yet.
final customerLedgerProvider = FutureProvider.family<List<CustomerLedgerEntry>, int>((
  ref,
  customerId,
) {
  return ref.watch(customerLedgerRepositoryProvider).getLedgerForCustomer(customerId);
});
