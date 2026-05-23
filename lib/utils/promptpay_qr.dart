/// PromptPay EMVCo QR payload generator (ThaiQR Payment specification).
///
/// Produces the exact 32–88 character string that Thai banking apps decode
/// from a PromptPay QR code. Pass the result to qr_flutter's [QrImageView]
/// (or any EMV-compatible renderer) to display it.
///
/// Supported merchant identifiers:
///   - phone (10 digits, e.g. 0812345678)
///   - citizen ID (13 digits)
///   - e-wallet ID (15 digits)
class PromptPayQR {
  /// Build the QR payload string.
  ///
  /// [rawId] accepts phone with or without hyphens/spaces.
  /// Pass [amount] for a dynamic QR (locked amount); omit for a static QR
  /// where the payer types the amount themselves.
  static String generate(String rawId, {double? amount}) {
    final digits = rawId.replaceAll(RegExp(r'[^\d]'), '');
    final String accountTag;
    final String accountValue;
    if (digits.length == 10) {
      // Phone: 08xxxxxxxx → 0066xxxxxxxxx (drop leading 0, prepend 0066)
      accountTag = '01';
      accountValue = '0066${digits.substring(1)}';
    } else if (digits.length == 13) {
      accountTag = '02';
      accountValue = digits;
    } else if (digits.length == 15) {
      accountTag = '03';
      accountValue = digits;
    } else {
      throw ArgumentError(
        'PromptPay ID must be 10 digits (phone), 13 (citizen ID), or 15 (e-wallet); got ${digits.length}',
      );
    }

    final buf = StringBuffer();
    // 00 — Payload Format Indicator (always "01")
    buf.write(_tlv('00', '01'));
    // 01 — Point of Initiation Method: 11=static (no amount), 12=dynamic (amount locked)
    buf.write(_tlv('01', amount != null ? '12' : '11'));
    // 29 — Merchant Account Information (PromptPay AID + account)
    final merchantInfo =
        _tlv('00', 'A000000677010111') + _tlv(accountTag, accountValue);
    buf.write(_tlv('29', merchantInfo));
    // 58 — Country
    buf.write(_tlv('58', 'TH'));
    // 53 — Currency (764 = THB per ISO 4217)
    buf.write(_tlv('53', '764'));
    // 54 — Amount (optional)
    if (amount != null) {
      buf.write(_tlv('54', amount.toStringAsFixed(2)));
    }
    // 63 — CRC, computed over everything up to and including "6304"
    final dataForCrc = '$buf' '6304';
    buf.write('6304${_crc16(dataForCrc)}');
    return buf.toString();
  }

  /// Add cents derived from [orderId] so two parallel orders of the same
  /// nominal amount produce different totals — the bank notification can
  /// then unambiguously match a deposit to an order.
  ///
  /// Returns the original amount plus 1–99 satang (0.01–0.99 baht).
  static double uniqueAmountFor(double baseAmount, String orderId) {
    // Hash the order ID into 1..99 satang. 0 is avoided so the cents
    // always differ from a "round number" deposit unrelated to an order.
    final cents = (orderId.hashCode.abs() % 99) + 1;
    return baseAmount + cents / 100;
  }

  static String _tlv(String tag, String value) {
    final len = value.length.toString().padLeft(2, '0');
    return '$tag$len$value';
  }

  /// CRC-16/CCITT-FALSE — poly 0x1021, init 0xFFFF, no XOR-out, no reflection.
  static String _crc16(String data) {
    var crc = 0xFFFF;
    for (final c in data.codeUnits) {
      crc ^= c << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
