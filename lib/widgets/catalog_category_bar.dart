import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keeps shop categories together, with catalog actions on the heading line.
class CatalogCategoryBar extends StatelessWidget {
  const CatalogCategoryBar({
    super.key,
    required this.actions,
    required this.choices,
    this.leading,
  });

  final List<Widget> actions;
  final List<Widget> choices;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Semantics(
                header: true,
                child:
                    Text('หมวดหมู่สินค้า', style: theme.textTheme.titleMedium),
              ),
              Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions),
            ],
          ),
        ),
        SizedBox(
            height:
                math.max(48, MediaQuery.textScalerOf(context).scale(20) + 24),
            child: Row(children: [
              if (leading != null)
                Padding(
                    padding: const EdgeInsets.only(left: 8), child: leading),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: choices.length,
                  itemBuilder: (_, index) => Align(child: choices[index]),
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                ),
              ),
            ])),
      ]),
    );
  }
}

ChoiceChip catalogCategoryChip(
  BuildContext context, {
  Key? key,
  required String label,
  required bool selected,
  required ValueChanged<bool> onSelected,
  IconData? icon,
}) {
  final cs = Theme.of(context).colorScheme;
  return ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: true,
    avatar: !selected && icon != null
        ? Icon(icon, size: 18, color: cs.onSurface)
        : null,
    selectedColor: cs.primary,
    backgroundColor: cs.surface,
    labelStyle: Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: selected ? cs.onPrimary : cs.onSurface),
    checkmarkColor: cs.onPrimary,
    side: BorderSide(color: selected ? cs.primary : cs.outline),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    onSelected: onSelected,
  );
}
