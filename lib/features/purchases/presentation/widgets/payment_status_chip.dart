import 'package:duka_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Display label for a Purchases.paymentStatus value ('paid', 'partial',
/// 'unpaid') — 'unpaid' reads as "Credit" since that's the term a small
/// shop actually uses for stock taken without paying up front.
String paymentStatusLabel(String paymentStatus) => switch (paymentStatus) {
  'paid' => 'Paid',
  'partial' => 'Partially paid',
  'unpaid' => 'Credit',
  _ => paymentStatus,
};

class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.paymentStatus});

  final String paymentStatus;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (paymentStatus) {
      'paid' => (AppColors.green50, AppColors.green700),
      'partial' => (AppColors.amber50, AppColors.amber800),
      'unpaid' => (AppColors.rust50, AppColors.rust700),
      _ => (AppColors.stone100, AppColors.stone600),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        paymentStatusLabel(paymentStatus),
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
