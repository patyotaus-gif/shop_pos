/// Suggestions only. Amount and time are never sufficient payment evidence.
bool bankPaymentCandidate(
    {required double expected,
    required double received,
    required DateTime createdAt,
    required DateTime observedAt,
    DateTime? transferredAt}) {
  if (!expected.isFinite ||
      !received.isFinite ||
      expected <= 0 ||
      received <= 0 ||
      (expected * 100).round() != (received * 100).round()) {
    return false;
  }
  if (transferredAt == null) return true;
  // Bad clocks / old notifications must not narrow the candidate set and
  // accidentally turn an ambiguous amount into a seemingly unique match.
  if (transferredAt.isAfter(observedAt.add(const Duration(minutes: 5))) ||
      transferredAt.isBefore(observedAt.subtract(const Duration(days: 1)))) {
    return true;
  }
  return !createdAt.isAfter(transferredAt.add(const Duration(minutes: 2)));
}
