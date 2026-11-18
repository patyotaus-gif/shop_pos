import 'pokpok_brand.dart';
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
                        // The bottom bar owns the home-indicator inset. Pages
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
                  child: _PhoneNavigationBar(
                    key: const ValueKey('phone-navigation'),
                    items: widget.items,
                    primaryCount: count,
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
                                          child: Row(children: [
                                            const PokpokMark(size: 28),
                                            const SizedBox(width: 6),
                                            const Flexible(
                                                child:
                                                    PokpokWordmark(width: 96)),
                                          ]))),
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

class _PhoneNavigationBar extends StatelessWidget {
  const _PhoneNavigationBar({
    super.key,
    required this.items,
    required this.primaryCount,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<AppNavigationItem> items;
  final int primaryCount;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = primaryCount + (items.length > primaryCount ? 1 : 0);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return Material(
      color: colors.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: LayoutBuilder(builder: (context, constraints) {
            // Each tab uses one track, and the selected tab uses two.
            final track = constraints.maxWidth / (count + 1);
            return Stack(children: [
              if (count > 0)
                AnimatedPositionedDirectional(
                  duration: duration,
                  curve: Curves.easeInOut,
                  start: selectedIndex * track + 2,
                  width: 2 * track - 4,
                  top: 12,
                  height: 40,
                  child: DecoratedBox(
                    key: const ValueKey('phone-navigation-indicator'),
                    decoration: ShapeDecoration(
                      color: colors.primaryContainer,
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              for (var i = 0; i < count; i++)
                AnimatedPositionedDirectional(
                  key: ValueKey(i < primaryCount ? items[i].label : 'เพิ่มเติม'),
                  duration: duration,
                  curve: Curves.easeInOut,
                  start: (i + (i > selectedIndex ? 1 : 0)) * track,
                  width: i == selectedIndex ? 2 * track : track,
                  top: 0,
                  bottom: 0,
                  child: _tab(context, i, duration),
                ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int index, Duration duration) {
    final item = index < primaryCount ? items[index] : null;
    final label = item?.label ?? 'เพิ่มเติม';
    final selected = index == selectedIndex;
    final badge = item?.badgeCount ?? 0;
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;
    final caption = selected
        ? Padding(
            padding: const EdgeInsetsDirectional.only(start: 4),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
          )
        : const SizedBox.shrink();
    void select() => onDestinationSelected(index);
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge ออเดอร์ใหม่' : label,
      onTap: select,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: select,
              customBorder: const StadiumBorder(),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Badge(
                  isLabelVisible: !selected && badge > 0,
                  label: Text(badge > 99 ? '99+' : '$badge'),
                  child: Icon(
                    (selected ? item?.selectedIcon : item?.icon) ?? Icons.more_horiz,
                    size: 22,
                    color: color,
                  ),
                ),
                Flexible(
                  child: duration == Duration.zero
                      ? caption
                      : AnimatedSize(
                          duration: duration,
                          curve: Curves.easeInOut,
                          alignment: AlignmentDirectional.centerStart,
                          child: caption,
                        ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
