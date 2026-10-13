import 'package:flutter/material.dart';

/// Categories belong to the shop's products, so saving a product also saves
/// its category without introducing a separate, device-local category list.
class ProductCategoryField extends StatelessWidget {
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
  Widget build(BuildContext context) => Autocomplete<String>(
        initialValue: TextEditingValue(text: initialValue),
        optionsBuilder: (value) => categories.where((category) =>
            category.toLowerCase().contains(value.text.trim().toLowerCase())),
        onSelected: onChanged,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
            TextFormField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (value) => onChanged(value.trim()),
          onFieldSubmitted: (_) => onSubmitted(),
          decoration: const InputDecoration(
            labelText: 'หมวดหมู่สินค้า',
            hintText: 'เช่น กาแฟ ขนมอบ อาหารจานเดียว',
            helperText:
                'พิมพ์หมวดใหม่หรือเลือกหมวดเดิม\nหมวดใหม่จะบันทึกพร้อมสินค้า',
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            final name = value?.trim() ?? '';
            if (name.isEmpty) return 'กรุณาระบุหมวดหมู่สินค้า';
            if (name == 'ทั้งหมด') return 'กรุณาใช้ชื่ออื่นแทนคำว่า ทั้งหมด';
            return null;
          },
        ),
      );
}
