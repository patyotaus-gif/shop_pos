import 'package:flutter/material.dart';

import '../models/modifier_group.dart';
import '../models/order_modifier.dart';
import '../models/product.dart';
import '../services/modifier_service.dart';

/// Result of the picker: the chosen modifier snapshots + an optional
/// free-text note to the kitchen (e.g. "ไม่ใส่ผัก").
typedef ModifierPick = ({List<OrderModifier> modifiers, String? notes});

/// Bottom sheet shown when adding a product to an order. Walks the customer
/// through each modifier group (radio or checkbox depending on `multiSelect`)
/// and collects an optional note. Opens even for products with no groups —
/// then it shows just the note field + Add. Returns null on cancel.
///
/// Required groups must have at least one option selected before "Add"
/// becomes active.
Future<ModifierPick?> showModifierPicker(
  BuildContext context, {
  required Product product,
}) {
  return showModalBottomSheet<ModifierPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ModifierPickerSheet(product: product),
  );
}

class _ModifierPickerSheet extends StatefulWidget {
  const _ModifierPickerSheet({required this.product});
  final Product product;

  @override
  State<_ModifierPickerSheet> createState() => _ModifierPickerSheetState();
}

class _ModifierPickerSheetState extends State<_ModifierPickerSheet> {
  Future<List<ModifierGroup>>? _future;
  // groupId → set of selected optionIds
  final Map<String, Set<String>> _selected = {};
  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _future = widget.product.modifierGroupIds.isEmpty
        ? Future.value(const <ModifierGroup>[])
        : ModifierService.getByIds(widget.product.modifierGroupIds);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  double _previewPrice(List<ModifierGroup> groups) {
    double total = widget.product.price;
    for (final g in groups) {
      final picks = _selected[g.id] ?? const <String>{};
      for (final o in g.options) {
        if (picks.contains(o.id)) total += o.priceAdjust;
      }
    }
    return total < 0 ? 0 : total;
  }

  bool _canSubmit(List<ModifierGroup> groups) {
    for (final g in groups) {
      if (g.required && (_selected[g.id]?.isEmpty ?? true)) return false;
    }
    return true;
  }

  void _toggle(ModifierGroup g, String optionId) {
    setState(() {
      final set = _selected.putIfAbsent(g.id, () => <String>{});
      if (g.multiSelect) {
        if (set.contains(optionId)) {
          set.remove(optionId);
        } else {
          set.add(optionId);
        }
      } else {
        set
          ..clear()
          ..add(optionId);
      }
    });
  }

  void _submit(List<ModifierGroup> groups) {
    final selected = <OrderModifier>[];
    for (final g in groups) {
      final picks = _selected[g.id] ?? const <String>{};
      for (final o in g.options) {
        if (picks.contains(o.id)) {
          selected.add(OrderModifier(
            groupId: g.id,
            groupName: g.name,
            optionId: o.id,
            optionName: o.name,
            priceAdjust: o.priceAdjust,
          ));
        }
      }
    }
    final note = _notesCtrl.text.trim();
    Navigator.pop(context, (
      modifiers: selected,
      notes: note.isEmpty ? null : note,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => FutureBuilder<List<ModifierGroup>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data ?? const <ModifierGroup>[];
          final canSubmit = _canSubmit(groups);
          final preview = _previewPrice(groups);

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.product.name,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              'ราคาเริ่มต้น ฿${widget.product.price.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    children: [
                      for (final g in groups)
                        _GroupSection(
                          group: g,
                          selected: _selected[g.id] ?? const <String>{},
                          onToggle: (optionId) => _toggle(g, optionId),
                        ),
                      // Free-text note to the kitchen — always available.
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 6),
                        child: Text('หมายเหตุถึงครัว',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      TextField(
                        controller: _notesCtrl,
                        maxLength: 200,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'เช่น ไม่ใส่ผัก, ไม่เผ็ด, แยกน้ำจิ้ม',
                          border: OutlineInputBorder(),
                          isDense: true,
                          counterText: '',
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border:
                          Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('รวม',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.6))),
                            Text('฿${preview.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed:
                                canSubmit ? () => _submit(groups) : null,
                            icon: const Icon(Icons.add),
                            label: const Text('เพิ่มเข้าตะกร้า'),
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  final ModifierGroup group;
  final Set<String> selected;
  final void Function(String optionId) onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unmet = group.required && selected.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(
            children: [
              Text(group.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              if (group.required)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: unmet
                        ? Colors.red.withValues(alpha: 0.15)
                        : cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('จำเป็น',
                      style: TextStyle(
                          fontSize: 10,
                          color: unmet ? Colors.red : cs.primary,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        for (final o in group.options)
          InkWell(
            onTap: () => onToggle(o.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  group.multiSelect
                      ? Icon(
                          selected.contains(o.id)
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: selected.contains(o.id)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.5),
                        )
                      : Icon(
                          selected.contains(o.id)
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected.contains(o.id)
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.5),
                        ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(o.name)),
                  if (o.priceAdjust != 0)
                    Text(
                      '${o.priceAdjust > 0 ? '+' : ''}฿${o.priceAdjust.toStringAsFixed(0)}',
                      style: TextStyle(
                          color: o.priceAdjust > 0
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ),
        const Divider(height: 24),
      ],
    );
  }
}
