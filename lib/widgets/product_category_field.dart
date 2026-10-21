import 'package:flutter/material.dart';

enum _CategoryAction { add }

/// Categories belong to the shop's products, so saving a product also saves
/// its category without introducing a separate, device-local category list.
class ProductCategoryField extends StatefulWidget {
  const ProductCategoryField({
    super.key,
    required this.initialValue,
    required this.categories,
    required this.onChanged,
  });

  final String initialValue;
  final List<String> categories;
  final ValueChanged<String> onChanged;

  @override
  State<ProductCategoryField> createState() => _ProductCategoryFieldState();
}

class _ProductCategoryFieldState extends State<ProductCategoryField> {
  late String _selected = widget.initialValue;
  int _menuRevision = 0;

  List<String> get _options => {
        ...widget.categories,
        if (_selected.isNotEmpty) _selected,
      }.where((name) => name.isNotEmpty && name != 'ทั้งหมด').toList()
        ..sort();

  Future<void> _add() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewCategoryDialog(categories: _options),
    );
    if (name == null || !mounted) return;
    setState(() => _selected = name);
    widget.onChanged(name);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Object>(
            key: ValueKey((_selected, _menuRevision)),
            initialValue: _options.contains(_selected) ? _selected : null,
            isExpanded: true,
            menuMaxHeight: 360,
            hint: const Text('กดเพื่อเลือกหมวดหมู่'),
            decoration: const InputDecoration(
              labelText: 'หมวดหมู่สินค้า',
              border: OutlineInputBorder(),
            ),
            items: [
              ..._options.map((name) => DropdownMenuItem<Object>(
                    value: name,
                    child: Text(name, overflow: TextOverflow.ellipsis),
                  )),
              const DropdownMenuItem<Object>(
                value: _CategoryAction.add,
                child: Row(children: [
                  Icon(Icons.add),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text('เพิ่มหมวดหมู่',
                        key: ValueKey('add-category-menu'),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ],
            onChanged: (value) {
              if (value == _CategoryAction.add) {
                // The menu action is not a category. Restore the previous
                // FormField value even when the name dialog is cancelled.
                setState(() => _menuRevision++);
                _add();
              } else if (value is String) {
                setState(() => _selected = value);
                widget.onChanged(value);
              }
            },
            validator: (value) => value is! String || value.isEmpty
                ? 'กรุณาเลือกหมวดหมู่สินค้า'
                : null,
          ),
          if (_options.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child:
                  Text('ยังไม่มีหมวดหมู่ แตะช่องด้านบนแล้วเลือกเพิ่มหมวดหมู่'),
            ),
        ],
      );
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog({required this.categories});
  final List<String> categories;

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final name = _name.text.trim();
    final existing = widget.categories
        .where((item) => item.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    Navigator.pop(context, existing ?? name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('เพิ่มหมวดหมู่'),
        scrollable: true,
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'ชื่อหมวดหมู่',
              hintText: 'เช่น เครื่องดื่ม ขนม อาหารจานเดียว',
              helperText: 'หมวดใหม่จะบันทึกพร้อมสินค้า',
              helperMaxLines: 2,
            ),
            validator: (value) {
              final name = value?.trim() ?? '';
              if (name.isEmpty) return 'กรุณาระบุชื่อหมวดหมู่';
              if (name == 'ทั้งหมด') return 'กรุณาใช้ชื่ออื่นแทนคำว่า ทั้งหมด';
              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(onPressed: _submit, child: const Text('เพิ่มและเลือก')),
        ],
      );
}
