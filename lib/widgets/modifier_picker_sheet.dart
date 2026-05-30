import 'package:flutter/material.dart';

import '../models/modifier_group.dart';
import '../models/order_modifier.dart';
import '../models/product.dart';
import '../services/modifier_service.dart';

/// Bottom sheet shown when a product with modifierGroupIds is picked.
/// Walks the customer through each group (radio or checkbox depending on
/// `multiSelect`) and returns the selected modifier snapshots ready to be
/// attached to a TableOrderItem. Returns null on cancel.
///
/// Required groups must have at least one option selected before "Add"
/// becomes active. Optional groups can be skipped entirely.
Future<List<OrderModifier>?> showModifierPicker(
  BuildContext context, {
  required Product product,
}) {
  return showModalBottomSheet<List<OrderModifier>>(
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

  @override
  void initState() {
    super.initState();
    _future = ModifierService.getByIds(widget.product.modifierGroupIds);
  }

  double _previewPrice(List<ModifierGroup> groups) {
    double total = widget.product.price;
    for (final g in groups) {
      final picks = _selected[g.id] ?? const <String>{};
      for (final o in g.options) {
        if (picks.contains(o.id)) total += o.priceAdjust;
      }
    }
    return total;
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
    Navigator.pop(context, selected);
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
          final groups = snap.data ?? const [];
          if (groups.isEmpty) {
            // Product had ids that resolve to nothing (deleted groups).
            // Just return no modifiers — caller will add the item plain.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pop(context, const <OrderModifier>[]);
            });
            return const SizedBox.shrink();
          }
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
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: groups.length,
                    itemBuilder: (_, i) => _GroupSection(
                      group: groups[i],
                      selected: _selected[groups[i].id] ?? const <String>{},
                      onToggle: (optionId) => _toggle(groups[i], optionId),
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding:
                        const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
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
