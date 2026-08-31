import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/customers/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(customerRepositoryProvider).watchCustomers();
});
