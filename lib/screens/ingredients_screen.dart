import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ingredient.dart';
import '../services/ingredient_service.dart';

/// วัตถุดิบ (Restaurant tier) — stock levels, weighted-average cost,
/// receive-goods and recount flows. Deduction itself is automatic
/// (server-side, per sale) so this screen is pure management.
class IngredientsScreen extends StatelessWidget {
  const IngredientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('วัตถุดิบ'), centerTitle: true),
      body: StreamBuilder<List<Ingredient>>(
        stream: IngredientService.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const [];
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ยังไม่มีวัตถุดิบ\n\nเพิ่มวัตถุดิบ (เช่น เส้น, ไข่, น้ำมัน) '
                  'แล้วไปผูก "สูตร" ในหน้าแก้เมนู — ขายแล้วระบบตัดสต็อกให้อัตโนมัติ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5)),
                ),
              ),
            );
          }
          final cs = Theme.of(context).colorScheme;
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: cs.primary.withValues(alpha: 0.06),
                padding: const EdgeInsets.all(12),
                child: Text(
                  'ขายเมนูที่มีสูตร → ตัดวัตถุดิบอัตโนมัติ · สต็อกติดลบได้ '
                  '(การขายไม่ถูกบล็อก — ติดลบ = ควรนับใหม่)',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.7)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _IngredientTile(ing: list[i]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มวัตถุดิบ'),
      ),
    );
  }
}

final _num = NumberFormat('#,##0.##', 'th_TH');

class _IngredientTile extends StatelessWidget {
  const _IngredientTile({required this.ing});
  final Ingredient ing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stockColor = ing.isNegative
        ? Colors.red
        : ing.isLow
            ? const Color(0xFFB45309)
            : cs.onSurface;
    return ListTile(
      title: Text(ing.name,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          'ต้นทุนเฉลี่ย ฿${_num.format(ing.avgCost)}/${ing.unit}'
          '${ing.lowStockThreshold > 0 ? ' · เตือนที่ ${_num.format(ing.lowStockThreshold)}' : ''}'),
      leading: ing.isNegative
          ? const Icon(Icons.error_outline, color: Colors.red)
          : ing.isLow
              ? const Icon(Icons.warning_amber_outlined,
                  color: Color(0xFFB45309))
              : const Icon(Icons.egg_outlined),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${_num.format(ing.stock)} ${ing.unit}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: stockColor)),
          if (ing.isNegative)
            const Text('ติดลบ — ควรนับใหม่',
                style: TextStyle(fontSize: 10, color: Colors.red)),
        ],
      ),
      onTap: () => _showActionsSheet(context, ing),
    );
  }
}

void _showActionsSheet(BuildContext context, Ingredient ing) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(ing.name,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                'คงเหลือ ${_num.format(ing.stock)} ${ing.unit} · '
                '฿${_num.format(ing.avgCost)}/${ing.unit}'),
          ),
          ListTile(
            leading: const Icon(Icons.add_shopping_cart),
            title: const Text('รับของเข้า'),
            subtitle: const Text('ซื้อเพิ่ม — คิดต้นทุนเฉลี่ยให้อัตโนมัติ'),
            onTap: () {
              Navigator.pop(ctx);
              _showReceiveDialog(context, ing);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('ปรับสต็อก (นับใหม่/ของเสีย)'),
            onTap: () {
              Navigator.pop(ctx);
              _showAdjustDialog(context, ing);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('แก้ไขชื่อ/หน่วย/จุดเตือน'),
            onTap: () {
              Navigator.pop(ctx);
              _showEditDialog(context, ing: ing);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('ลบวัตถุดิบ',
                style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('ลบ "${ing.name}"?'),
                  content: const Text(
                      'เมนูที่มีวัตถุดิบนี้ในสูตรจะข้ามการตัดตัวนี้ไป'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('ยกเลิก')),
                    FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('ลบ')),
                  ],
                ),
              );
              if (ok == true) await IngredientService.delete(ing.id);
            },
          ),
        ],
      ),
    ),
  );
}

void _showEditDialog(BuildContext context, {Ingredient? ing}) {
  final name = TextEditingController(text: ing?.name ?? '');
  final unit = TextEditingController(text: ing?.unit ?? '');
  final threshold = TextEditingController(
      text: (ing?.lowStockThreshold ?? 0) > 0
          ? _num.format(ing!.lowStockThreshold)
          : '');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ing == null ? 'เพิ่มวัตถุดิบ' : 'แก้ไขวัตถุดิบ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'ชื่อ (เช่น ไข่ไก่)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: unit,
            decoration: const InputDecoration(
                labelText: 'หน่วย (เช่น ฟอง, กรัม, มล.)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: threshold,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'จุดเตือนใกล้หมด (เว้นว่าง = ไม่เตือน)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty || unit.text.trim().isEmpty) return;
            final t = double.tryParse(
                    threshold.text.trim().replaceAll(',', '')) ??
                0;
            if (ing == null) {
              await IngredientService.add(Ingredient(
                id: '',
                name: name.text.trim(),
                unit: unit.text.trim(),
                lowStockThreshold: t,
                createdAt: DateTime.now(),
              ));
            } else {
              await IngredientService.update(Ingredient(
                id: ing.id,
                name: name.text.trim(),
                unit: unit.text.trim(),
                stock: ing.stock,
                avgCost: ing.avgCost,
                lowStockThreshold: t,
                createdAt: ing.createdAt,
              ));
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('บันทึก'),
        ),
      ],
    ),
  );
}

void _showReceiveDialog(BuildContext context, Ingredient ing) {
  final qty = TextEditingController();
  final price = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('รับของเข้า — ${ing.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: qty,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'จำนวนที่รับ (${ing.unit})',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: price,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'ราคารวมที่จ่าย (บาท)',
                prefixText: '฿',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () async {
            final q = double.tryParse(qty.text.trim().replaceAll(',', ''));
            final p =
                double.tryParse(price.text.trim().replaceAll(',', ''));
            if (q == null || q <= 0 || p == null || p < 0) return;
            await IngredientService.receiveStock(ing,
                qty: q, totalPrice: p);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('รับเข้า'),
        ),
      ],
    ),
  );
}

void _showAdjustDialog(BuildContext context, Ingredient ing) {
  final stock = TextEditingController(text: _num.format(ing.stock));
  final note = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('ปรับสต็อก — ${ing.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: stock,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'จำนวนที่นับได้จริง (${ing.unit})',
                border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(
                labelText: 'เหตุผล (เช่น นับใหม่, ของเสีย)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () async {
            final s =
                double.tryParse(stock.text.trim().replaceAll(',', ''));
            if (s == null) return;
            await IngredientService.adjustStock(ing,
                newStock: s, note: note.text.trim());
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('บันทึก'),
        ),
      ],
    ),
  );
}
