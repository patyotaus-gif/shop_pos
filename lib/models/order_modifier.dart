/// Snapshot of a chosen modifier embedded inside a line item.
///
/// We snapshot the names + price at order time so that editing the parent
/// ModifierGroup later (renaming "เผ็ดมาก" → "เผ็ดสุด", changing prices)
/// doesn't rewrite history on past orders / receipts / reports.
class OrderModifier {
  final String groupId;
  final String groupName;
  final String optionId;
  final String optionName;
  final double priceAdjust;

  const OrderModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    this.priceAdjust = 0,
  });

  factory OrderModifier.fromMap(Map<String, dynamic> m) => OrderModifier(
        groupId: m['groupId'] ?? '',
        groupName: m['groupName'] ?? '',
        optionId: m['optionId'] ?? '',
        optionName: m['optionName'] ?? '',
        priceAdjust: (m['priceAdjust'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'groupName': groupName,
        'optionId': optionId,
        'optionName': optionName,
        'priceAdjust': priceAdjust,
      };
}

/// Used when merging line items — two items with the same product but
/// different modifier sets must stay as separate rows. Modifiers are
/// considered equal when they cover the same option ids regardless of
/// order.
bool modifiersEqual(List<OrderModifier> a, List<OrderModifier> b) {
  if (a.length != b.length) return false;
  final aIds = a.map((m) => m.optionId).toList()..sort();
  final bIds = b.map((m) => m.optionId).toList()..sort();
  for (var i = 0; i < aIds.length; i++) {
    if (aIds[i] != bIds[i]) return false;
  }
  return true;
}
