/// Parses incoming-funds notifications from Thai banking apps into a
/// canonical [BankIncomingTransfer] record so [NotificationListenerHandler]
/// can match them against pending PromptPay orders.
///
/// Each bank pushes notifications in its own wording, so we keep one
/// matcher per package. Adding a new bank = add a new entry to [_parsers].
library;

class BankIncomingTransfer {
  /// Amount in THB. Always positive.
  final double amount;

  /// Free-form sender label as it appears in the notification, e.g. "นาย ก
  /// ABCDEF" or "Mr. K. SOMSAK". Useful for showing the shop owner who paid.
  final String? sender;

  /// Which banking app produced the notification.
  final String bankCode;

  const BankIncomingTransfer({
    required this.amount,
    required this.bankCode,
    this.sender,
  });

  @override
  String toString() => 'BankIncomingTransfer($amount THB from $sender via $bankCode)';
}

class BankNotificationParser {
  /// Returns null when [packageName]/[text] don't look like an incoming
  /// transfer the parser knows about. Returning null is the normal case —
  /// most notifications are unrelated (promos, login alerts, etc).
  static BankIncomingTransfer? parse({
    required String packageName,
    required String title,
    required String text,
  }) {
    final parser = _parsers[packageName];
    if (parser == null) return null;
    return parser(title, text);
  }

  /// Banks the listener actively understands. Other apps' notifications
  /// are ignored entirely.
  static const Set<String> supportedPackages = {
    _kPlus,
    _scbEasy,
    _krungthaiNext,
    _bualuang,
    _ttbTouch,
    _kma,
  };

  static const _kPlus = 'com.kasikorn.retail.mbanking.wap';
  static const _scbEasy = 'com.scb.phone';
  static const _krungthaiNext = 'com.krungthai.aob';
  static const _bualuang = 'com.bbl.mobilebanking';
  static const _ttbTouch = 'com.ttb.touch.mb';
  static const _kma = 'com.krungsri.kma';

  static final Map<String, BankIncomingTransfer? Function(String, String)>
      _parsers = {
    _kPlus: _parseKPlus,
    _scbEasy: _parseScbEasy,
    _krungthaiNext: _parseKrungthai,
    _bualuang: _parseBualuang,
    _ttbTouch: _parseTtbTouch,
    _kma: _parseKma,
  };

  // ───── K PLUS (KBank) ─────
  // Typical text:
  //   "เงินเข้าบัญชี xxx-x-x1234-x จำนวน 30.24 บาท จาก นาย ก ABCDEF เมื่อ ..."
  static BankIncomingTransfer? _parseKPlus(String title, String text) {
    final body = '$title $text';
    if (!body.contains('เงินเข้า')) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'KBANK', sender: sender);
  }

  // ───── SCB EASY ─────
  // Typical text:
  //   "เงินเข้า 30.24 บาท จาก K. SOMSAK ABCDEF บัญชี xxx-x-x..."
  static BankIncomingTransfer? _parseScbEasy(String title, String text) {
    final body = '$title $text';
    if (!body.contains('เงินเข้า')) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'SCB', sender: sender);
  }

  // ───── Krungthai NEXT ─────
  static BankIncomingTransfer? _parseKrungthai(String title, String text) {
    final body = '$title $text';
    if (!(body.contains('รับโอน') || body.contains('เงินเข้า'))) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'KTB', sender: sender);
  }

  // ───── Bualuang mBanking (BBL) ─────
  static BankIncomingTransfer? _parseBualuang(String title, String text) {
    final body = '$title $text';
    if (!body.contains('เงินเข้า')) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'BBL', sender: sender);
  }

  // ───── TTB Touch ─────
  static BankIncomingTransfer? _parseTtbTouch(String title, String text) {
    final body = '$title $text';
    if (!body.contains('เงินเข้า')) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'TTB', sender: sender);
  }

  // ───── Krungsri KMA ─────
  static BankIncomingTransfer? _parseKma(String title, String text) {
    final body = '$title $text';
    if (!body.contains('เงินเข้า')) return null;
    final amount = _firstThaiAmount(body);
    if (amount == null) return null;
    final sender = _afterKeyword(body, 'จาก ');
    return BankIncomingTransfer(amount: amount, bankCode: 'BAY', sender: sender);
  }

  // ───────────── Helpers ─────────────

  /// Finds the first amount-looking token followed by "บาท" or "THB" or
  /// just floating before a space. Handles "30.24", "30.24 บาท",
  /// "30,500.24 บาท".
  static double? _firstThaiAmount(String body) {
    final r = RegExp(r'([0-9]{1,3}(?:[,\s][0-9]{3})*\.[0-9]{2})\s*(?:บาท|THB)?');
    final m = r.firstMatch(body);
    if (m == null) return null;
    final raw = m.group(1)!.replaceAll(RegExp(r'[,\s]'), '');
    return double.tryParse(raw);
  }

  /// Grabs the text after [keyword] up to the next punctuation or sentence
  /// break. e.g. "จาก นาย ก ABC เมื่อ ..." with keyword "จาก " returns
  /// "นาย ก ABC".
  static String? _afterKeyword(String body, String keyword) {
    final idx = body.indexOf(keyword);
    if (idx < 0) return null;
    final tail = body.substring(idx + keyword.length);
    // Stop at common Thai punctuation/connectors that end the sender clause.
    final stop = RegExp(r'(เมื่อ|ผ่าน|วันที่|เวลา|บัญชี|\n|,)');
    final endMatch = stop.firstMatch(tail);
    final raw = endMatch == null ? tail : tail.substring(0, endMatch.start);
    final cleaned = raw.trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
