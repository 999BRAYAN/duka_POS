/// Thrown by [InventoryService.adjustStock] when no reason is given. A
/// reason is mandatory for manual adjustments — it's the audit trail for
/// these until a dedicated audit-log UI exists, so an empty one defeats the
/// point.
class MissingAdjustmentReasonException implements Exception {
  const MissingAdjustmentReasonException();

  @override
  String toString() => 'A reason is required for a manual stock adjustment.';
}
