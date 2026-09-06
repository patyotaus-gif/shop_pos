import 'package:flutter/material.dart';

class AppNavigationItem {
  const AppNavigationItem({
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

/// Keeps every page mounted while placing all destinations on the left.
/// Narrow screens use stacked icon/labels; wide screens use full menu rows.
class SideNavigationShell extends StatelessWidget {
  const SideNavigationShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final expanded = constraints.maxWidth >= 1000;
            final width = expanded ? 192.0 : 72.0;
            return Row(
              children: [
                SizedBox(
                  width: width,
                  child: Material(
                    color: colors.surfaceContainerLow,
                    child: SafeArea(
                      left: false,
                      right: false,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 60,
                            child: Center(
                              child: Semantics(
                                label: 'Pokpok',
                                child: ExcludeSemantics(
                                  child: expanded
                                      ? Text('pokpok',
                                          style: TextStyle(
                                            color: colors.primary,
                                            fontSize: 25,
                                            fontWeight: FontWeight.w700,
                                          ))
                                      : Icon(Icons.storefront,
                                          color: colors.primary, size: 28),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              key: const PageStorageKey('side-navigation'),
                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final selected = selectedIndex == index;
                                final foreground = selected
                                    ? colors.onPrimary
                                    : colors.onSurfaceVariant;
                                final icon = Badge(
                                  isLabelVisible: item.badgeCount > 0,
                                  label: Text(item.badgeCount > 99
                                      ? '99+'
                                      : '${item.badgeCount}'),
                                  child: Icon(
                                    selected ? item.selectedIcon : item.icon,
                                    color: foreground,
                                    size: 23,
                                  ),
                                );
                                final label = Text(
                                  item.label,
                                  textAlign: expanded
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: expanded ? 14 : 11,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                );
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Semantics(
                                    button: true,
                                    selected: selected,
                                    label: item.badgeCount > 0
                                        ? '${item.label}, ${item.badgeCount} ออเดอร์ใหม่'
                                        : item.label,
                                    onTap: () => onSelected(index),
                                    child: ExcludeSemantics(
                                      child: Tooltip(
                                        message: item.label,
                                        child: Material(
                                          color: selected
                                              ? colors.primary
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: InkWell(
                                            key: ValueKey('nav-${item.label}'),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            onTap: () => onSelected(index),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                  minHeight: 60),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: expanded ? 12 : 2,
                                                  vertical: 10,
                                                ),
                                                child: expanded
                                                    ? Row(children: [
                                                        icon,
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(child: label),
                                                      ])
                                                    : Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          icon,
                                                          const SizedBox(
                                                              height: 6),
                                                          label,
                                                        ],
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                    width: 1, thickness: 1, color: colors.outlineVariant),
                Expanded(
                  child: IndexedStack(
                    index: selectedIndex,
                    children: [
                      for (final item in items)
                        KeyedSubtree(
                          key: ValueKey(item.label),
                          child: item.screen,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
