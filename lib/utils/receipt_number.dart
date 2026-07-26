/// Per-day receipt numbering — pure helpers so they're unit-testable and
/// shared by the POS + table-close checkout transactions.
///
/// Format: `YYMMDD-NNN` where YY is the 2-digit Buddhist year, e.g.
/// 690726-001 = 2569-07-26, first receipt of the day.
library;

/// The "day" key for [date] in the counter — `YYMMDD` (Buddhist year).
String receiptDay(DateTime date) {
  final be = (date.year + 543) % 100;
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${be.toString().padLeft(2, '0')}$mm$dd';
}

/// Format a full receipt number from a day key + sequence.
String formatReceiptNo(String dayKey, int seq) =>
    '$dayKey-${seq.toString().padLeft(3, '0')}';

/// Next counter state given the stored counter (`counterDay`/`counterSeq`,
/// null when the doc doesn't exist yet) and today's day key. Rolls the
/// sequence back to 1 on a new day.
({String day, int seq}) nextReceiptSeq(
    String? counterDay, String todayKey, int counterSeq) {
  if (counterDay == todayKey) {
    return (day: todayKey, seq: counterSeq + 1);
  }
  return (day: todayKey, seq: 1);
}
