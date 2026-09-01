import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/providers.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_ledger_repository_impl.dart';
import 'package:duka_pos/features/customers/data/repositories/customer_repository_impl.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_ledger_repository.dart';
import 'package:duka_pos/features/customers/domain/repositories/customer_repository.dart';
import 'package:duka_pos/features/customers/domain/services/customer_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepositoryImpl(ref.watch(databaseProvider));
});

final customerLedgerRepositoryProvider = Provider<CustomerLedgerRepository>((ref) {
  return CustomerLedgerRepositoryImpl(ref.watch(databaseProvider));
});

final customerServiceProvider = Provider<CustomerService>((ref) {
  return CustomerService(
    ref.watch(customerRepositoryProvider),
    ref.watch(authorizationServiceProvider),
  );
});
