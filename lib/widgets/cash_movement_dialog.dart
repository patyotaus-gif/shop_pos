import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({super.key, this.pending, required this.save});
  final Map<String, dynamic>? pending;
  final Future<void> Function(String kind, double amount, String reason) save;
  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _reason;
  late String _kind;
  late bool _locked;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _kind = widget.pending?['kind'] as String? ?? 'cashOut';
    _amount = TextEditingController(
        text: widget.pending?['amount']?.toString() ?? '');
    _reason =
        TextEditingController(text: widget.pending?['reason'] as String? ?? '');
    _locked = widget.pending != null;
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _locked = true;
      _error = null;
    });
    try {
      await widget.save(
          _kind, double.parse(_amount.text.trim()), _reason.text.trim());
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is FirebaseFunctionsException
              ? (e.message ?? 'ยืนยันรายการไม่สำเร็จ ลองอีกครั้งด้วยข้อมูลเดิม')
              : e is StateError
                  ? e.message.toString()
                  : 'ยืนยันรายการไม่สำเร็จ ลองอีกครั้งด้วยข้อมูลเดิม';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('บันทึกเงินสดเข้า–ออก'),
        scrollable: true,
        content: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'บันทึกในรอบที่เปิดอยู่และวันที่ปัจจุบัน เงินออกลดเงินในลิ้นชัก โดยยอดขายยังเท่าเดิม'),
              if (widget.pending != null)
                const Text(
                    'มีรายการรอยืนยัน ยืนยันข้อมูลเดิมเพื่อป้องกันบันทึกซ้ำ'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                for (final kind in ['cashIn', 'cashOut'])
                  ChoiceChip(
                      label: Text(kind == 'cashIn' ? 'เงินเข้า' : 'เงินออก'),
                      selected: _kind == kind,
                      onSelected:
                          _locked ? null : (_) => setState(() => _kind = kind)),
              ]),
              TextFormField(
                  controller: _amount,
                  readOnly: _locked,
                  decoration:
                      const InputDecoration(labelText: 'จำนวนเงิน (บาท)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (text) {
                    final value = double.tryParse(text?.trim() ?? '');
                    return value == null ||
                            !value.isFinite ||
                            value <= 0 ||
                            value > 1e9 ||
                            !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text!.trim())
                        ? 'กรอกจำนวนเงินมากกว่า 0 ไม่เกิน 2 ตำแหน่ง'
                        : null;
                  }),
              const SizedBox(height: 8),
              TextFormField(
                  controller: _reason,
                  readOnly: _locked,
                  maxLength: 300,
                  decoration: const InputDecoration(
                      labelText: 'เหตุผล', hintText: 'เช่น ซื้อน้ำแข็ง'),
                  validator: (text) => text == null || text.trim().isEmpty
                      ? 'ระบุเหตุผลเพื่อให้ตรวจสอบย้อนหลังได้'
                      : null),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ])),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('ปิด')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? 'กำลังยืนยัน…'
                  : _locked
                      ? 'ยืนยันรายการเดิม'
                      : 'บันทึก')),
        ],
      ));
}
