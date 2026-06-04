import 'package:flutter/material.dart';

import '../models/shop.dart';
import '../models/staff_member.dart';
import '../services/entitlements.dart';
import '../services/staff_service.dart';

/// Manage PIN-based staff profiles. Reached from Settings (Full/Restaurant
/// only). The owner profile is implicit — this screen manages the extra
/// cashier profiles up to the tier's user cap.
class StaffScreen extends StatelessWidget {
  const StaffScreen({super.key, required this.tier});
  final ShopTier tier;

  @override
  Widget build(BuildContext context) {
    // maxUsers includes the owner. -1 = unlimited (Restaurant).
    final cap = Entitlements.maxUsers(tier);

    return Scaffold(
      appBar: AppBar(title: const Text('พนักงาน'), centerTitle: true),
      body: StreamBuilder<List<StaffMember>>(
        stream: StaffService.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final staff = snap.data ?? const [];

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        cap < 0
                            ? 'เพิ่มพนักงานได้ไม่จำกัด · พนักงานเลือกตัวเองด้วย PIN ตอนขาย'
                            : 'แผนนี้รองรับ $cap คน (รวมเจ้าของ) · พนักงานใช้ PIN ระบุตัวตนตอนขาย',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: staff.isEmpty
                    ? Center(
                        child: Text('ยังไม่มีพนักงานเพิ่ม',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.5))),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: staff.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => _StaffTile(staff: staff[i]),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: StreamBuilder<List<StaffMember>>(
        stream: StaffService.watchAll(),
        builder: (context, snap) {
          final count = snap.data?.length ?? 0;
          final extraAllowed = cap < 0 ? -1 : (cap - 1);
          final atCap = extraAllowed >= 0 && count >= extraAllowed;
          if (atCap) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: () => _openForm(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('เพิ่มพนักงาน'),
          );
        },
      ),
    );
  }

  void _openForm(BuildContext context, [StaffMember? existing]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StaffForm(existing: existing),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.staff});
  final StaffMember staff;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primary.withValues(alpha: 0.12),
        child: Text(
          staff.name.isNotEmpty ? staff.name.characters.first : '?',
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(staff.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('PIN ${staff.pin} · ${staff.role.label}'),
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: cs.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _StaffForm(existing: staff),
        ),
      ),
    );
  }
}

class _StaffForm extends StatefulWidget {
  const _StaffForm({this.existing});
  final StaffMember? existing;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  late final TextEditingController _name;
  late final TextEditingController _pin;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _pin = TextEditingController(text: widget.existing?.pin ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final pin = _pin.text.trim();
    if (name.isEmpty) {
      _toast('กรุณากรอกชื่อ');
      return;
    }
    if (pin.length != 4 || int.tryParse(pin) == null) {
      _toast('PIN ต้องเป็นตัวเลข 4 หลัก');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await StaffService.update(
            widget.existing!.copyWith(name: name, pin: pin));
      } else {
        await StaffService.create(name: name, pin: pin);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast('บันทึกไม่สำเร็จ: $e');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบพนักงาน'),
        content: Text('ลบ "${widget.existing!.name}" ใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await StaffService.delete(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_isEdit ? 'แก้ไขพนักงาน' : 'เพิ่มพนักงาน',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_isEdit)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _delete,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'ชื่อพนักงาน',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'PIN 4 หลัก',
              hintText: 'ใช้ระบุตัวตนตอนขาย',
              prefixIcon: Icon(Icons.pin_outlined),
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_isEdit ? 'บันทึก' : 'เพิ่มพนักงาน'),
          ),
        ],
      ),
    );
  }
}
