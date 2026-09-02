import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/features/sales/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every sale, newest first — what the sales-history screen lists and what
/// a void updates in place.
final salesStreamProvider = StreamProvider<List<Sale>>((ref) {
  return ref.watch(saleRepositoryProvider).watchSales();
});
