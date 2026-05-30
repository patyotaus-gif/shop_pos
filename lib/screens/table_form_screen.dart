import 'package:flutter/material.dart';

import '../models/restaurant_table.dart';
import '../services/table_service.dart';

/// Create or edit a single table. For edit, also supports delete (only if
/// the table is currently available — busy tables block deletion).
class TableFormScreen extends StatefulWidget {
  const TableFormScreen({super.key, this.table});
  final RestaurantTable? table;

  bool get _isEdit => table != null;

  @override
  State<TableFormScreen> createState() => _TableFormScreenState();
}

class _TableFormScreenState extends State<TableFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final TextEditingController _section;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.table?.name ?? '');
    _capacity =
        TextEditingController(text: (widget.table?.capacity ?? 4).toString());
    _section = TextEditingController(text: widget.table?.section ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _section.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (widget._isEdit) {
        await TableService.updateTable(widget.table!.copyWith(
          name: _name.text.trim(),
          capacity: int.tryParse(_capacity.text) ?? 4,
          section: _section.text.trim().isEmpty ? null : _section.text.trim(),
        ));
      } else {
        await TableService.createTable(
          name: _name.text.trim(),
          capacity: int.tryParse(_capacity.text) ?? 4,
          section: _section.text.trim().isEmpty ? null : _section.text.trim(),
        );
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
    if (widget.table!.status == TableStatus.occupied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบไม่ได้ — โต๊ะนี้กำลังมีลูกค้า')),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบโต๊ะ'),
        content: Text('ต้องการลบ "${widget.table!.name}" ใช่ไหม?'),
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
      await TableService.deleteTable(widget.table!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget._isEdit ? 'แก้ไขโต๊ะ' : 'เพิ่มโต๊ะ'),
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
                labelText: 'ชื่อ/เลขโต๊ะ *',
                hintText: 'เช่น 1, A2, Bar-3',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อโต๊ะ' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'จำนวนที่นั่ง',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'ใส่ตัวเลขมากกว่า 0';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _section,
              decoration: const InputDecoration(
                labelText: 'โซน (ไม่บังคับ)',
                hintText: 'เช่น ในร้าน, ระเบียง, Bar',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(widget._isEdit ? 'บันทึก' : 'เพิ่มโต๊ะ'),
            ),
          ],
        ),
      ),
    );
  }
}
