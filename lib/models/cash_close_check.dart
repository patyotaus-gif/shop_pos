class CashCloseIssue {
  final String type;
  final String id;
  final String label;
  final String message;

  const CashCloseIssue(
      {required this.type,
      required this.id,
      required this.label,
      required this.message});

  factory CashCloseIssue.fromMap(Map<dynamic, dynamic> map) => CashCloseIssue(
        type: map['type'] as String? ?? '',
        id: map['id'] as String? ?? '',
        label: map['label'] as String? ?? '',
        message: map['message'] as String? ?? 'รายการที่ต้องตรวจสอบ',
      );
}

class CashCloseCheck {
  final bool canClose;
  final bool closed;
  final int issueCount;
  final int futureOrderCount;
  final List<CashCloseIssue> issues;

  const CashCloseCheck(
      {required this.canClose,
      required this.closed,
      required this.issueCount,
      required this.futureOrderCount,
      required this.issues});

  factory CashCloseCheck.fromMap(Map<dynamic, dynamic> map) {
    final issues = (map['issues'] as List? ?? [])
        .map((e) => CashCloseIssue.fromMap(e as Map))
        .toList();
    final count = (map['issueCount'] as num?)?.toInt() ?? issues.length;
    return CashCloseCheck(
      canClose: map['canClose'] == true &&
          map['closed'] != true &&
          count == 0 &&
          issues.isEmpty,
      closed: map['closed'] == true,
      issueCount: count,
      futureOrderCount: (map['futureOrderCount'] as num? ?? 0).toInt(),
      issues: issues,
    );
  }
}
