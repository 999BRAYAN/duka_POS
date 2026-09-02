import 'package:duka_pos/core/authorization/authorization_exceptions.dart';
import 'package:duka_pos/core/authorization/current_user_provider.dart';
import 'package:duka_pos/core/authorization/permission.dart';
import 'package:duka_pos/core/authorization/providers.dart';
import 'package:duka_pos/core/database/database.dart';
import 'package:duka_pos/core/printing/receipt_pdf.dart';
import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:duka_pos/features/customers/presentation/providers.dart';
import 'package:duka_pos/features/products/presentation/providers/product_list_providers.dart';
import 'package:duka_pos/features/sales/data/providers.dart';
import 'package:duka_pos/features/sales/domain/exceptions.dart';
import 'package:duka_pos/features/sales/presentation/providers/cart_provider.dart';
import 'package:duka_pos/features/sales/presentation/providers/order_form_providers.dart';
import 'package:duka_pos/features/sales/presentation/widgets/sale_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

final _amountFormat = NumberFormat('#,##0.00');

/// Step two of a sale: confirm what was ordered, then take the money.
///
/// The order is shown as a settled list here — quantities cannot be changed
/// on this screen. Editing goes back a step, so the total someone is being
/// asked to pay can't shift while they are paying it.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _amountPaidController = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// Set when the last attempt was refused for breaching a credit limit, so
  /// the override is offered against that specific refusal rather than
  /// standing permanently on the screen as a way to skip the check.
  bool _creditLimitRefused = false;

  @override
  void dispose() {
    _amountPaidController.dispose();
    super.dispose();
  }

  double get _subtotal => ref.read(cartSubtotalProvider);
  double get _total => (_subtotal - ref.read(orderDiscountProvider))
      .clamp(0, double.infinity)
      .toDouble();

  Future<void> _complete({required bool overrideCreditLimit}) async {
    final cart = ref.read(cartProvider);
    final user = ref.read(currentUserProvider);
    if (cart.isEmpty) return;
    if (user == null) {
      setState(() => _error = 'No one is signed in.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final customerId = ref.read(orderCustomerIdProvider);
    final total = _total;
    // Only a named customer can leave a balance: with nobody selected there
    // is no one to charge the shortfall to, so a walk-in sale is paid in
    // full by definition.
    final amountPaid = customerId == null
        ? total
        : (double.tryParse(_amountPaidController.text) ?? 0);

    try {
      final sale = await ref
          .read(saleServiceProvider)
          .completeSale(
            cart: cart,
            customerId: customerId,
            userId: user.id,
            paymentMethod: ref.read(orderPaymentMethodProvider),
            amountPaid: amountPaid,
            discount: ref.read(orderDiscountProvider),
            overrideCreditLimit: overrideCreditLimit,
          );

      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      resetOrder(ref);

      await showSaleConfirmationDialog(
        context,
        invoiceNumber: sale.invoiceNumber,
        total: _amountFormat.format(sale.total),
        onPrintReceipt: () => _printReceipt(sale),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } on CreditLimitExceededException catch (e) {
      setState(() {
        _error = '$e';
        _creditLimitRefused = true;
      });
    } on UnauthorizedException catch (e) {
      setState(() => _error = '$e');
    } on InsufficientStockException catch (e) {
      setState(() => _error = '$e');
    } on PriceBelowFloorException catch (e) {
      setState(() => _error = '$e');
    } on CustomerRequiredForCreditException catch (e) {
      setState(() => _error = '$e');
    } catch (e) {
      setState(() => _error = 'Could not complete this sale: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _printReceipt(Sale sale) async {
    final items = await ref
        .read(saleRepositoryProvider)
        .getItemsForSale(sale.id);
    final products =
        ref.read(productsStreamProvider).valueOrNull ?? const <Product>[];
    final customers =
        ref.read(customersStreamProvider).valueOrNull ?? const <Customer>[];

    await printReceipt(
      sale: sale,
      items: items,
      productsById: {for (final product in products) product.id: product},
      cashier: ref.read(currentUserProvider),
      customer: sale.customerId == null
          ? null
          : customers.where((c) => c.id == sale.customerId).firstOrNull,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final discount = ref.watch(orderDiscountProvider);
    final total = (subtotal - discount).clamp(0, double.infinity).toDouble();
    final customerId = ref.watch(orderCustomerIdProvider);
    final paymentMethod = ref.watch(orderPaymentMethodProvider);

    final customers =
        (ref.watch(customersStreamProvider).valueOrNull ?? const <Customer>[])
            // The seeded walk-in row is excluded: the dropdown's own null option
            // already means "walk-in customer".
            .where((c) => !c.isWalkIn)
            .toList();
    final selectedCustomer = customers
        .where((c) => c.id == customerId)
        .firstOrNull;

    final amountPaid = customerId == null
        ? total
        : (double.tryParse(_amountPaidController.text) ?? 0);
    final balanceDue = (total - amountPaid)
        .clamp(0, double.infinity)
        .toDouble();
    final canOverride = ref
        .watch(authorizationServiceProvider)
        .can(Permission.overrideCreditLimit);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirm & pay')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('The order is empty.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to the order'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm & pay')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _CheckoutSteps(),
            const SizedBox(height: 16),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Below this the order table and the payment card cannot
                  // both hold their width, so payment moves underneath.
                  final narrow = constraints.maxWidth < 860;
                  final order = Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 44,
                              dataRowMinHeight: 42,
                              dataRowMaxHeight: 42,
                              columns: const [
                                DataColumn(label: Text('Item')),
                                DataColumn(label: Text('Qty'), numeric: true),
                                DataColumn(label: Text('Price'), numeric: true),
                                DataColumn(label: Text('Total'), numeric: true),
                              ],
                              rows: [
                                for (final line in cart)
                                  DataRow(
                                    cells: [
                                      DataCell(Text(line.name)),
                                      DataCell(
                                        Text(
                                          _amountFormat.format(line.quantity),
                                        ),
                                      ),
                                      DataCell(
                                        Text(_amountFormat.format(line.price)),
                                      ),
                                      DataCell(
                                        Text(
                                          _amountFormat.format(line.lineTotal),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _summaryRow(context, 'Subtotal', subtotal),
                                if (discount > 0)
                                  _summaryRow(context, 'Discount', -discount),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Total',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      _amountFormat.format(total),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  final payment = Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Payment',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int?>(
                              initialValue: customerId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Customer',
                                isDense: true,
                              ),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('Walk-in customer'),
                                ),
                                for (final customer in customers)
                                  DropdownMenuItem<int?>(
                                    value: customer.id,
                                    child: Text(
                                      '${customer.name} · owes '
                                      '${_amountFormat.format(customer.currentBalance)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                // A newly-picked customer defaults to
                                // paying in full: leaving a balance should
                                // be a deliberate act, not what happens by
                                // forgetting to type anything.
                                final wasWalkIn = customerId == null;
                                ref
                                        .read(orderCustomerIdProvider.notifier)
                                        .state =
                                    value;
                                if (value != null && wasWalkIn) {
                                  _amountPaidController.text = total
                                      .toStringAsFixed(2);
                                }
                                setState(() => _creditLimitRefused = false);
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: paymentMethod,
                              decoration: const InputDecoration(
                                labelText: 'Payment method',
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'cash',
                                  child: Text('Cash'),
                                ),
                                DropdownMenuItem(
                                  value: 'mpesa',
                                  child: Text('M-Pesa'),
                                ),
                                DropdownMenuItem(
                                  value: 'card',
                                  child: Text('Card'),
                                ),
                                DropdownMenuItem(
                                  value: 'credit',
                                  child: Text('Credit'),
                                ),
                              ],
                              onChanged: (value) =>
                                  ref
                                          .read(
                                            orderPaymentMethodProvider.notifier,
                                          )
                                          .state =
                                      value ?? 'cash',
                            ),
                            if (customerId != null) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _amountPaidController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Amount paid now',
                                  isDense: true,
                                ),
                              ),
                            ],
                            if (selectedCustomer != null && balanceDue > 0) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SemanticColors.warningSurface(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Remaining ${_amountFormat.format(balanceDue)} goes on '
                                  "${selectedCustomer.name}'s account — now "
                                  '${_amountFormat.format(selectedCustomer.currentBalance)} '
                                  'of ${_amountFormat.format(selectedCustomer.creditLimit)}.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: SemanticColors.warning(context),
                                  ),
                                ),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: SemanticColors.debtSurface(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      _error!,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: SemanticColors.debt(context),
                                      ),
                                    ),
                                    if (_creditLimitRefused) ...[
                                      const SizedBox(height: 10),
                                      if (canOverride)
                                        OutlinedButton(
                                          onPressed: _submitting
                                              ? null
                                              : () => _complete(
                                                  overrideCreditLimit: true,
                                                ),
                                          child: const Text(
                                            'Override and complete',
                                          ),
                                        )
                                      else
                                        Text(
                                          'A manager can approve this.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: SemanticColors.debt(context),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _submitting
                                  ? null
                                  : () => _complete(overrideCreditLimit: false),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Text(
                                  _submitting
                                      ? 'Saving…'
                                      : 'Complete sale · ${_amountFormat.format(total)}',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back, size: 18),
                              label: const Text('Back to the order'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );

                  if (narrow) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [order, const SizedBox(height: 16), payment],
                      ),
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: order),
                      const SizedBox(width: 24),
                      SizedBox(width: 360, child: payment),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: SemanticColors.muted(context),
              fontSize: 13,
            ),
          ),
          Text(
            _amountFormat.format(value),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CheckoutSteps extends StatelessWidget {
  const _CheckoutSteps();

  @override
  Widget build(BuildContext context) {
    final muted = SemanticColors.muted(context);
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Icon(Icons.check_circle, size: 18, color: muted),
        const SizedBox(width: 7),
        Text(
          'Order built',
          style: TextStyle(
            fontSize: 12.5,
            color: muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.arrow_forward, size: 14, color: muted),
        ),
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: primary),
          child: Text(
            '2',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'Confirm & take payment',
          style: TextStyle(
            fontSize: 12.5,
            color: primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
