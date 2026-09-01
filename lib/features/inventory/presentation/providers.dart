import 'package:duka_pos/features/inventory/data/providers.dart';
import 'package:duka_pos/features/inventory/domain/models/product_stock_valuation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final stockValuationStreamProvider = StreamProvider<List<ProductStockValuation>>((ref) {
  return ref.watch(stockValuationRepositoryProvider).watchStockValuation();
});
