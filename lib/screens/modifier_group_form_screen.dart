import 'package:flutter/material.dart';

import '../models/modifier_group.dart';
import '../services/modifier_service.dart';

/// Create/edit a modifier group. Options are edited inline (add row /
/// remove row / set name + price adjust). Save commits the whole group.
class ModifierGroupFormScreen extends StatefulWidget {
  const ModifierGroupFormScreen({super.key, this.group});
  final ModifierGroup? group;

  bool get _isEdit => group != null;

  @override
  State<ModifierGroupFormScreen> createState() =>
      _ModifierGroupFormScreenState();
}

class _ModifierGroupFormScreenState extends State<ModifierGroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _required = false;
  bool _multiSelect = false;
  late List<_OptionDraft> _options;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    _name = TextEditingController(text: g?.name ?? '');
    _required = g?.required ?? false;
    _multiSelect = g?.multiSelect ?? false;
    _options = (g?.options ?? const [])
        .map((o) => _OptionDraft(
              id: o.id,
              name: o.name,
              priceAdjust: o.priceAdjust,
            ))
        .toList();
    if (_options.isEmpty) {
      _options.add(_OptionDraft.empty());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final cleaned =
        _options.where((o) => o.nameCtrl.text.trim().isNotEmpty).toList();
    if (cleaned.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเพิ่มอย่างน้อย 1 ตัวเลือก')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final options = cleaned.map((o) => o.toOption()).toList();
      if (widget._isEdit) {
        await ModifierService.update(widget.group!.copyWith(
          name: _name.text.trim(),
          required: _required,
          multiSelect: _multiSelect,
          options: options,
        ));
      } else {
        await ModifierService.create(ModifierGroup(
          id: '',
          name: _name.text.trim(),
          required: _required,
          multiSelect: _multiSelect,
          options: options,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบกลุ่มนี้?'),
        content: Text(
            '"${widget.group!.name}" จะหายไปจากสินค้าที่ผูกไว้ (ลูกค้าจะเลือกไม่ได้)'),
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
    if (confirm == true) {
      await ModifierService.delete(widget.group!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _addOptionRow() {
    setState(() => _options.add(_OptionDraft.empty()));
  }

  void _removeOptionRow(int i) {
    setState(() {
      _options[i].dispose();
      _options.removeAt(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._isEdit ? 'แก้ไขกลุ่ม' : 'สร้างกลุ่มใหม่'),
        centerTitle: true,
        actions: [
          if (widget._isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'ชื่อกลุ่ม *',
                hintText: 'เช่น ระดับเผ็ด, ขนาด, เพิ่มเติม',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อกลุ่ม' : null,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _required,
              onChanged: (v) => setState(() => _required = v),
              title: const Text('จำเป็นต้องเลือก'),
              subtitle: const Text('ลูกค้าต้องเลือกก่อนเพิ่มลงตะกร้า'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _multiSelect,
              onChanged: (v) => setState(() => _multiSelect = v),
              title: const Text('เลือกได้หลายอัน'),
              subtitle: Text(_multiSelect
                  ? 'Checkbox — เลือกได้หลายตัวเลือก'
                  : 'Radio — เลือกได้แค่ 1 ตัวเลือก'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Text('ตัวเลือก',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (var i = 0; i < _options.length; i++) ...[
              _OptionRow(
                draft: _options[i],
                onRemove:
                    _options.length > 1 ? () => _removeOptionRow(i) : null,
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _addOptionRow,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มตัวเลือก'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(widget._isEdit ? 'บันทึก' : 'สร้างกลุ่ม'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionDraft {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController priceCtrl;

  _OptionDraft({
    required this.id,
    required String name,
    required double priceAdjust,
  })  : nameCtrl = TextEditingController(text: name),
        priceCtrl = TextEditingController(
            text: priceAdjust == 0 ? '' : priceAdjust.toStringAsFixed(0));

  factory _OptionDraft.empty() => _OptionDraft(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '',
        priceAdjust: 0,
      );

  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
  }

  ModifierOption toOption() => ModifierOption(
        id: id,
        name: nameCtrl.text.trim(),
        priceAdjust: double.tryParse(priceCtrl.text) ?? 0,
      );
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.draft, this.onRemove});
  final _OptionDraft draft;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: draft.nameCtrl,
            decoration: const InputDecoration(
              labelText: 'ชื่อตัวเลือก',
              hintText: 'เช่น เผ็ดน้อย, ขนาดใหญ่',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: draft.priceCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: const InputDecoration(
              labelText: 'ราคา ฿+/-',
              hintText: '0',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          color: Colors.red,
          onPressed: onRemove,
        ),
      ],
    );
  }
}
