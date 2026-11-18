import 'package:flutter/material.dart';
import 'compact_action.dart';

class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.title, {super.key, this.helper});
  final String title;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium)),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ]),
    );
  }
}

class SettingsSection {
  const SettingsSection(
      {required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;
}

class SettingsSections extends StatefulWidget {
  const SettingsSections({super.key, required this.sections});
  final List<SettingsSection> sections;
  @override
  State<SettingsSections> createState() => _SettingsSectionsState();
}

class _SettingsSectionsState extends State<SettingsSections> {
  int _selected = 0;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final theme = Theme.of(context);
        final reducedMotion = MediaQuery.disableAnimationsOf(context);
        final navigation = List.generate(widget.sections.length, (i) {
          final section = widget.sections[i];
          final selected = _selected == i;
          return Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(section.icon, size: 20),
                  labelStyle: theme.textTheme.labelLarge,
                  chipAnimationStyle: reducedMotion
                      ? ChipAnimationStyle(
                          selectAnimation: AnimationStyle.noAnimation)
                      : null,
                  label: Stack(children: [
                    Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(section.title)),
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 0,
                      child: AnimatedScale(
                        scale: selected ? 1 : 0,
                        alignment: Alignment.bottomLeft,
                        duration: reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 240),
                        curve: Curves.easeInOut,
                        child: Container(
                            height: 2, color: theme.colorScheme.primary),
                      ),
                    ),
                  ]),
                  selected: selected,
                  onSelected: (_) {
                    FocusScope.of(context).unfocus();
                    setState(() => _selected = i);
                  }));
        });
        final content = Expanded(
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                        key: PageStorageKey(_selected),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(20),
                        children: [
                          for (final child
                              in widget.sections[_selected].children)
                            if (child is ButtonStyleButton)
                              CompactAction(child: child)
                            else
                              child,
                        ]))));
        return SafeArea(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                        width: 250,
                        child: ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (final item in navigation)
                                Align(
                                    alignment: AlignmentDirectional.centerStart,
                                    child: item),
                            ])),
                    const VerticalDivider(width: 1),
                    content,
                  ])
                : Column(children: [
                    SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: navigation)),
                    const Divider(height: 1),
                    content,
                  ]));
      });
}
