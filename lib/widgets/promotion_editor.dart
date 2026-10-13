import 'package:flutter/material.dart';
import '../models/product.dart';
import '../utils/money_format.dart';

double? promotionalPrice(double base, String input, {required bool percent}) {
  final value = double.tryParse(input.trim());
  if (!base.isFinite ||
      base <= 0 ||
      value == null ||
      !value.isFinite ||
      value <= 0) {
    return null;
  }
  if (percent && value >= 100) return null;
  final price =
      ((percent ? base * (1 - value / 100) : value) * 100).round() / 100;
  return price > 0 && price < base ? price : null;
}

class PromotionEditor extends StatefulWidget {
  const PromotionEditor(
      {super.key, required this.product, required this.onSave});
  final Product product;
  final Future<void> Function(double? price, DateTime? until) onSave;

  @override
  State<PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends State<PromotionEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _price;
  DateTime? _until;
  bool _percent = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(
        text: widget.product.salePrice?.toStringAsFixed(2) ?? '');
    _until = widget.product.saleUntil;
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _until != null && _until!.isAfter(today) ? _until! : today;
    final last = DateTime(now.year + 10, 12, 31);
    final picked = await showDatePicker(
        context: context,
        initialDate: initial.isAfter(last) ? last : initial,
        firstDate: today,
        lastDate: last);
    if (picked != null && mounted) {
      setState(() => _until =
          DateTime(picked.year, picked.month, picked.day, 23, 59, 59, 999));
    }
  }

  Future<void> _save({bool remove = false}) async {
    if (!remove && !_form.currentState!.validate()) return;
    if (!remove && _until != null && !_until!.isAfter(DateTime.now())) {
      setState(() => _error =
          'โปรโมชั่นเดิมหมดอายุแล้ว กรุณาเลือกวันสิ้นสุดใหม่หรือไม่กำหนดวัน');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
          remove
              ? null
              : promotionalPrice(widget.product.price, _price.text,
                  percent: _percent),
          remove ? null : _until);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message.toString()
              : 'บันทึกไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วลองใหม่';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview =
        promotionalPrice(widget.product.price, _price.text, percent: _percent);
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('ตั้งโปรโมชั่นสินค้า'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('ราคาปกติ ${formatBaht(widget.product.price)}'),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final percent in [false, true])
                        ChoiceChip(
                            label: Text(
                                percent ? 'ลดเป็นเปอร์เซ็นต์' : 'กำหนดราคาโปร'),
                            selected: _percent == percent,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() {
                                      _percent = percent;
                                      _price.clear();
                                    })),
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _price,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText:
                                _percent ? 'ส่วนลด (%)' : 'ราคาโปร (บาท)',
                            border: const OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                        validator: (value) => promotionalPrice(
                                    widget.product.price, value ?? '',
                                    percent: _percent) ==
                                null
                            ? (_percent
                                ? 'ระบุส่วนลดมากกว่า 0 และน้อยกว่า 100%'
                                : 'ราคาโปรต้องมากกว่า 0 และต่ำกว่าราคาปกติ')
                            : null),
                    if (preview != null) ...[
                      const SizedBox(height: 8),
                      Text(
                          'ลูกค้าจ่าย ${formatBaht(preview)} · ลด ${formatBaht(widget.product.price - preview)}'),
                      if (preview < widget.product.costPrice)
                        Text('ราคาโปรต่ำกว่าต้นทุนสินค้า',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 12),
                    const Text('เริ่มใช้ทันทีหลังบันทึก'),
                    TextButton.icon(
                        onPressed: _saving ? null : _pickDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(_until == null
                            ? 'กำหนดวันสิ้นสุด (ไม่บังคับ)'
                            : 'ถึง ${_until!.day}/${_until!.month}/${_until!.year} สิ้นวัน')),
                    if (_until != null)
                      TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _until = null),
                          child: const Text('ไม่กำหนดวันสิ้นสุด')),
                    const Text(
                        'ส่วนลดเปอร์เซ็นต์จะคำนวณเป็นราคาโปรจากราคาปกติขณะบันทึก'),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ]),
            ))),
        actions: [
          if (widget.product.salePrice != null)
            TextButton(
                onPressed: _saving ? null : () => _save(remove: true),
                child: const Text('ยกเลิกโปรโมชั่น')),
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('กลับ')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'กำลังบันทึก…' : 'บันทึกโปรโมชั่น')),
        ],
      ),
    );
  }
}
