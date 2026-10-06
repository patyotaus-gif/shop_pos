import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';

class PickupSettingsCard extends StatefulWidget {
  const PickupSettingsCard({super.key, required this.initial});
  final Map<String, dynamic> initial;
  @override
  State<PickupSettingsCard> createState() => _PickupSettingsCardState();
}

class _PickupSettingsCardState extends State<PickupSettingsCard> {
  final _form = GlobalKey<FormState>();
  late bool _enabled;
  late int _open, _close, _prep, _capacity, _slot;
  late Set<int> _days;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _enabled = d['enabled'] == true;
    _open = (d['openMinute'] as num?)?.toInt() ?? 540;
    _close = (d['closeMinute'] as num?)?.toInt() ?? 1080;
    _prep = (d['prepMinutes'] as num?)?.toInt() ?? 30;
    _capacity = (d['capacity'] as num?)?.toInt() ?? 5;
    _slot = (d['slotMinutes'] as num?)?.toInt() ?? 15;
    _days =
        ((d['weekdays'] as List?) ?? [0, 1, 2, 3, 4, 5, 6]).cast<int>().toSet();
  }

  String _time(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  Future<void> _choose(bool opening) async {
    final m = opening ? _open : _close;
    final value = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60));
    if (value == null || !mounted) return;
    setState(() {
      if (opening) {
        _open = value.hour * 60 + value.minute;
      } else {
        _close = value.hour * 60 + value.minute;
      }
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    if (_enabled && (_close - _open < _slot || _days.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'เลือกวันเปิดรับ และเวลาปิดหลังเวลาเปิดอย่างน้อยหนึ่งช่วง')));
      return;
    }
    setState(() => _saving = true);
    try {
      await SettingsService.saveSettings({
        'pickup': {
          'enabled': _enabled,
          'openMinute': _open,
          'closeMinute': _close,
          'prepMinutes': _prep,
          'capacity': _capacity,
          'slotMinutes': _slot,
          'weekdays': _days.toList()..sort(),
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกเวลารับสินค้าแล้ว')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('บันทึกไม่สำเร็จ ตรวจอินเทอร์เน็ตและสิทธิ์เจ้าของร้าน')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AuthService.isStaff) return const SizedBox.shrink();
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ให้ลูกค้าเลือกเวลามารับ'),
                        subtitle: const Text(
                            'สั่งออนไลน์รับที่ร้าน • ล่วงหน้าได้ 7 วัน • เวลาประเทศไทย'),
                        value: _enabled,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _enabled = v)),
                    if (_enabled) ...[
                      Wrap(spacing: 8, children: [
                        OutlinedButton(
                            onPressed: _saving ? null : () => _choose(true),
                            child: Text('เริ่มรับ ${_time(_open)}')),
                        OutlinedButton(
                            onPressed: _saving ? null : () => _choose(false),
                            child: Text('สิ้นสุด ${_time(_close)}')),
                      ]),
                      Wrap(spacing: 4, children: [
                        for (int i = 0; i < 7; i++)
                          FilterChip(
                            label: Text(const [
                              'อา.',
                              'จ.',
                              'อ.',
                              'พ.',
                              'พฤ.',
                              'ศ.',
                              'ส.'
                            ][i]),
                            selected: _days.contains(i),
                            onSelected: _saving
                                ? null
                                : (v) => setState(() {
                                      v ? _days.add(i) : _days.remove(i);
                                    }),
                          )
                      ]),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                          initialValue: _slot,
                          decoration: const InputDecoration(
                              labelText: 'ความยาวแต่ละช่วง'),
                          items: [
                            for (final m in [15, 30, 60])
                              DropdownMenuItem(value: m, child: Text('$m นาที'))
                          ],
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _slot = v!)),
                      TextFormField(
                          initialValue: '$_prep',
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'เวลาเตรียมขั้นต่ำ (นาที)'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 5 || n > 240
                                ? 'กรอก 5–240 นาที'
                                : null;
                          },
                          onSaved: (v) => _prep = int.parse(v!)),
                      TextFormField(
                          initialValue: '$_capacity',
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'จำนวนออเดอร์สูงสุดต่อช่วง'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 100
                                ? 'กรอก 1–100 ออเดอร์'
                                : null;
                          },
                          onSaved: (v) => _capacity = int.parse(v!)),
                      const SizedBox(height: 8),
                      const Text(
                          'ออเดอร์รอชำระยังจองช่วงเวลาไว้ ร้านยกเลิกออเดอร์ที่ไม่ใช้เพื่อคืนที่ว่าง การเปลี่ยนเวลาร้านไม่เปลี่ยนนัดรับเดิม',
                          style: TextStyle(fontSize: 12)),
                    ],
                    const SizedBox(height: 8),
                    FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving
                            ? 'กำลังบันทึก...'
                            : 'บันทึกเวลารับสินค้า')),
                  ],
                ))));
  }
}
