import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepositoryImpl(ref.watch(databaseProvider));
});
