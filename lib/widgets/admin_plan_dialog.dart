import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../services/admin_service.dart';
import '../utils/operation_error.dart';

class AdminPlanDialog extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Future<void> Function(Map<String, dynamic>)? save;
  const AdminPlanDialog({super.key, required this.shop, this.save});
  @override
  State<AdminPlanDialog> createState() => _AdminPlanDialogState();
}

class _AdminPlanDialogState extends State<AdminPlanDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final TextEditingController _locations;
  late String _tier, _cycle;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _pending;
  @override
  void initState() {
    super.initState();
    _tier = widget.shop['tier'] as String? ?? 'full';
    _cycle = widget.shop['plan'] as String? ?? 'monthly';
    _locations =
        TextEditingController(text: '${widget.shop['locations'] ?? 1}');
  }

  @override
  void dispose() {
    _reason.dispose();
    _locations.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final payload = <String, dynamic>{
      'shopId': widget.shop['id'],
      'tier': _tier,
      'billingCycle': _cycle,
      'locations': int.parse(_locations.text.trim()),
      'reason': _reason.text.trim(),
      'expected': {
        'tier': widget.shop['tier'] ?? 'full',
        'plan': widget.shop['plan'] ?? 'monthly',
        'locations': widget.shop['locations'] ?? 1,
      }
    };
    if (_pending == null ||
        ['tier', 'billingCycle', 'locations', 'reason']
            .any((k) => _pending![k] != payload[k])) {
      _pending = {...payload, 'requestId': const Uuid().v4()};
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.save ?? AdminService.changePlan)(_pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = operationError(e);
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('แก้แผนผู้ใช้'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${widget.shop['name'] ?? ''}\n${widget.shop['email'] ?? ''}'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: _tier,
                          decoration:
                              const InputDecoration(labelText: 'แพ็กเกจ'),
                          items: const [
                            DropdownMenuItem(
                                value: 'solo', child: Text('Solo')),
                            DropdownMenuItem(
                                value: 'lite', child: Text('Lite')),
                            DropdownMenuItem(
                                value: 'full', child: Text('Full')),
                            DropdownMenuItem(
                                value: 'restaurant', child: Text('Restaurant'))
                          ],
                          onChanged:
                              _busy ? null : (v) => setState(() => _tier = v!)),
                      DropdownButtonFormField<String>(
                          initialValue: _cycle,
                          decoration:
                              const InputDecoration(labelText: 'รอบบิลในแอป'),
                          items: const [
                            DropdownMenuItem(
                                value: 'monthly', child: Text('รายเดือน')),
                            DropdownMenuItem(
                                value: 'yearly', child: Text('รายปี'))
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _cycle = v!)),
                      TextFormField(
                          controller: _locations,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'จำนวนสาขา'),
                          validator: (v) {
                            final count = int.tryParse(v?.trim() ?? '');
                            return count == null || count < 1 || count > 10000
                                ? 'ระบุ 1–10,000 สาขา'
                                : null;
                          }),
                      TextFormField(
                          controller: _reason,
                          enabled: !_busy,
                          maxLength: 500,
                          decoration: const InputDecoration(
                              labelText: 'เหตุผลที่เปลี่ยนแผน'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'กรุณาระบุเหตุผล'
                              : null),
                      const Text(
                          'คงสถานะสมาชิกและวันหมดอายุเดิม การเปลี่ยนนี้ไม่เรียกเก็บเงินหรือเปลี่ยนสัญญา Stripe หากต้องการเพิ่มวัน ให้ใช้เปิดใช้แบบจ่ายเงิน'),
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      if (_busy) const LinearProgressIndicator(),
                    ]))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('ยืนยันเปลี่ยนแผน'))
        ],
      ));
}
