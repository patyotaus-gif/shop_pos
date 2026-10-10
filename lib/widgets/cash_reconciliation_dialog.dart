import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/operation_error.dart';

class CashReconciliationDialog extends StatefulWidget {
  const CashReconciliationDialog(
      {super.key,
      required this.movementId,
      required this.amountMinor,
      required this.method,
      required this.kind,
      required this.openedAt,
      required this.openingFloat,
      this.recordedAt,
      required this.save});
  final String movementId, method, kind;
  final int amountMinor;
  final DateTime openedAt;
  final DateTime? recordedAt;
  final double openingFloat;
  final Future<void> Function(String reason, String cashTreatment) save;

  @override
  State<CashReconciliationDialog> createState() =>
      _CashReconciliationDialogState();
}

class _CashReconciliationDialogState extends State<CashReconciliationDialog> {
  final _reason = TextEditingController();
  String? _treatment;
  String? _error;
  bool _saving = false;
  final _money = NumberFormat('#,##0.00', 'th_TH');
  final _date = DateFormat('dd/MM/yyyy HH:mm');
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        _reason.text.trim().isEmpty ||
        (widget.method == 'cash' && _treatment == null)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(_reason.text.trim(),
          widget.method == 'cash' ? _treatment! : 'nonCash');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = operationError(error);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('ตรวจเงินและจัดเข้ารอบ'),
        scrollable: true,
        content: SizedBox(
            width: 460,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${switch (widget.kind) {
                'refund' => 'คืนเงิน',
                'debtPayment' => 'รับชำระหนี้',
                _ => 'ขายสินค้า'
              }} · ${switch (widget.method) {
                'cash' => 'เงินสด',
                'transfer' => 'โอน',
                'qr' => 'QR',
                'credit' => 'ขายเชื่อ',
                _ => 'ออนไลน์'
              }}'),
              Text('฿${_money.format(widget.amountMinor / 100)}',
                  style: Theme.of(context).textTheme.titleLarge),
              SelectableText('รายการ ${widget.movementId}'),
              if (widget.recordedAt != null)
                Text('บันทึกเมื่อ ${_date.format(widget.recordedAt!)}'),
              const Divider(),
              Text('จัดเข้ารอบที่เปิด ${_date.format(widget.openedAt)}'),
              Text('เงินตั้งต้น ฿${_money.format(widget.openingFloat)}'),
              const Text(
                  'ตรวจว่าเป็นรายการของร้านจริง ระบบจะรวมรายการนี้ในรอบปัจจุบัน โดยเก็บวันขายและยอดเดิม ไม่รับเงินหรือตัดสต็อกซ้ำ'),
              if (widget.method == 'cash') ...[
                const SizedBox(height: 12),
                const Text('ยอดนี้รวมอยู่ในเงินตั้งต้นแล้วหรือยัง?'),
                DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'เลือกวิธีนับเงินสด'),
                    items: const [
                      DropdownMenuItem(
                          value: 'addToDrawer',
                          child: Text('ยังไม่รวม · เพิ่ม/ลดจากเงินตั้งต้น')),
                      DropdownMenuItem(
                          value: 'includedInOpeningFloat',
                          child: Text('รวมแล้ว · ไม่นับเงินสดซ้ำ')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _treatment = value)),
                const Text(
                    'หากเป็นเงินคืน ให้เลือกตามว่าเงินตั้งต้นเป็นยอดหลังคืนเงินแล้วหรือยัง'),
                if (_treatment != null)
                  Text(
                      'ผลต่อเงินสดควรมี: ฿${_money.format(_treatment == 'includedInOpeningFloat' ? 0 : widget.amountMinor / 100)}'),
              ],
              const SizedBox(height: 12),
              TextField(
                  controller: _reason,
                  enabled: !_saving,
                  maxLength: 300,
                  decoration: const InputDecoration(
                      labelText: 'เหตุผล / หลักฐานที่ตรวจแล้ว'),
                  onChanged: (_) => setState(() {})),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ])),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: _saving ||
                      _reason.text.trim().isEmpty ||
                      (widget.method == 'cash' && _treatment == null)
                  ? null
                  : _save,
              child: Text(_saving ? 'กำลังบันทึก…' : 'ยืนยันจัดเข้ารอบ')),
        ],
      ));
}
