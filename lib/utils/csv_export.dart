/// Explicit money cells remain numeric; untrusted text is never inferred as a
/// number/formula, including phone numbers, names and document references.
class CsvMoney {
  const CsvMoney(this.value);
  final num value;
}

String csvRow(Iterable<Object?> cells) => cells.map((cell) {
      if (cell is CsvMoney) {
        if (!cell.value.isFinite) throw ArgumentError('Invalid CSV money');
        final rounded = (cell.value * 100).round();
        return (rounded / 100).toStringAsFixed(2);
      }
      if (cell is num) {
        if (!cell.isFinite) throw ArgumentError('Invalid CSV number');
        return cell.toString();
      }
      var text = cell?.toString() ?? '';
      // Excel/Sheets can interpret quoted cells as formulas. Prefix text only.
      if (RegExp(r'^[\s\u0000-\u001f\u007f\ufeff]*[=+\-@]').hasMatch(text) ||
          RegExp(r'^[\t\r\n]').hasMatch(text)) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }).join(',');

const salesReportBasis =
    'ตามวันที่ขาย หักบิลคืนเงินจากวันขายเดิม แม้คืนคนละวัน '
    'ยอดย้อนหลังจึงเปลี่ยนได้ ดูเงินรับ–คืนตามวันที่บันทึกที่หน้าเงินเข้า–ออก';

const movementReportBasis =
    'ตามวันที่บันทึกเงิน แยกจากวันที่ขายและวันที่เกิดรายการ '
    'รวมรับชำระหนี้และคืนเงิน ไม่ใช่ยอดขายหรือยอดปิดรอบ '
    'รายการเก่าก่อนเริ่มบันทึกบัญชีอาจไม่มีข้อมูล';
