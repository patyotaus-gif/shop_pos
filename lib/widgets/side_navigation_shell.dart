import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Keeps pages mounted across phone bottom-navigation and tablet sidebars.
class SideNavigationShell extends StatefulWidget {
  const SideNavigationShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.statusBanner,
  });

  final List<AppNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? statusBanner;
  @override
  State<SideNavigationShell> createState() => _SideNavigationShellState();
}

class _SideNavigationShellState extends State<SideNavigationShell> {
  bool _collapsed = false;
  bool _touched = false;
  final _pageKeys = <String, GlobalKey>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && !_touched) {
        setState(
            () => _collapsed = prefs.getBool('sidebar-collapsed') ?? false);
      }
    } catch (_) {}
  }

  Future<void> _toggle() async {
    setState(() {
      _touched = true;
      _collapsed = !_collapsed;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sidebar-collapsed', _collapsed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              final count = widget.items.length > 4 ? 4 : widget.items.length;
              return Column(children: [
                Expanded(
                    child: MediaQuery.removePadding(
                        context: context,
                        removeBottom: true,
                        // NavigationBar owns the home-indicator inset. Pages
                        // above it must not reserve that same space again.
                        child: IndexedStack(
                            index: widget.selectedIndex,
                            children: [
                              for (final item in widget.items)
                                KeyedSubtree(
                                    key: _pageKeys.putIfAbsent(
                                        item.label, GlobalKey.new),
                                    child: item.screen),
                            ]))),
                if (widget.statusBanner != null)
                  MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: widget.statusBanner!),
                MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: NavigationBar(
                    height: 64,
                    selectedIndex: widget.selectedIndex < count
                        ? widget.selectedIndex
                        : count,
                    onDestinationSelected: (index) async {
                      if (index < count) {
                        widget.onSelected(index);
                        return;
                      }
                      final chosen = await showModalBottomSheet<int>(
                          context: context,
                          builder: (context) => SafeArea(
                                  child: ListView(shrinkWrap: true, children: [
                                for (var i = count;
                                    i < widget.items.length;
                                    i++)
                                  ListTile(
                                      leading: Icon(widget.items[i].icon),
                                      title: Text(widget.items[i].label),
                                      selected: widget.selectedIndex == i,
                                      onTap: () => Navigator.pop(context, i)),
                              ])));
                      if (chosen != null && mounted) widget.onSelected(chosen);
                    },
                    destinations: [
                      for (var i = 0; i < count; i++)
                        NavigationDestination(
                            icon: Badge(
                                isLabelVisible: widget.items[i].badgeCount > 0,
                                label: Text(widget.items[i].badgeCount > 99
                                    ? '99+'
                                    : '${widget.items[i].badgeCount}'),
                                child: Icon(widget.items[i].icon)),
                            selectedIcon: Icon(widget.items[i].selectedIcon),
                            label: widget.items[i].label),
                      if (widget.items.length > count)
                        const NavigationDestination(
                            icon: Icon(Icons.more_horiz), label: 'เพิ่มเติม'),
                    ],
                  ),
                ),
              ]);
            }
            final expanded = constraints.maxWidth >= 1000 && !_collapsed;
            final width = _collapsed
                ? 56.0
                : expanded
                    ? 192.0
                    : 72.0;
            return Row(
              children: [
                SizedBox(
                  width: width,
                  child: Material(
                    color: colors.surface,
                    child: SafeArea(
                      left: false,
                      right: false,
                      child: Column(
                        children: [
                          SizedBox(
                              height: 60,
                              child: Row(children: [
                                if (expanded)
                                  Expanded(
                                      child: Padding(
                                          padding:
                                              const EdgeInsets.only(left: 16),
                                          child: Text('pokpok',
                                              style: TextStyle(
                                                  color: colors.primary,
                                                  fontSize: 23,
                                                  fontWeight:
                                                      FontWeight.w700)))),
                                Expanded(
                                    flex: expanded ? 0 : 1,
                                    child: IconButton(
                                        key: const ValueKey('toggle-sidebar'),
                                        tooltip:
                                            _collapsed ? 'ขยายเมนู' : 'ยุบเมนู',
                                        onPressed: _toggle,
                                        icon: Icon(
                                            _collapsed
                                                ? Icons.menu
                                                : Icons.menu_open,
                                            color: colors.primary))),
                              ])),
                          Expanded(
                            child: ListView.builder(
                              key: const PageStorageKey('side-navigation'),
                              padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
                              itemCount: widget.items.length,
                              itemBuilder: (context, index) {
                                final item = widget.items[index];
                                final selected = widget.selectedIndex == index;
                                final foreground = selected
                                    ? colors.onPrimaryContainer
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
                                    onTap: () => widget.onSelected(index),
                                    child: ExcludeSemantics(
                                      child: Tooltip(
                                        message: item.label,
                                        child: Material(
                                          color: selected
                                              ? colors.primaryContainer
                                              : Colors.transparent,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: InkWell(
                                            key: ValueKey('nav-${item.label}'),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            onTap: () =>
                                                widget.onSelected(index),
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
                                                          if (!_collapsed)
                                                            const SizedBox(
                                                                height: 6),
                                                          if (!_collapsed)
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
                  child: Column(children: [
                    Expanded(
                        child: IndexedStack(
                      index: widget.selectedIndex,
                      children: [
                        for (final item in widget.items)
                          KeyedSubtree(
                            key: _pageKeys.putIfAbsent(
                                item.label, GlobalKey.new),
                            child: item.screen,
                          ),
                      ],
                    )),
                    if (widget.statusBanner != null) widget.statusBanner!
                  ]),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
