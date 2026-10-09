import 'package:flutter/material.dart';
import 'compact_action.dart';

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
        final navigation = List.generate(widget.sections.length, (i) {
          final section = widget.sections[i];
          return Padding(
              padding: const EdgeInsets.all(4),
              child: ChoiceChip(
                  avatar: Icon(section.icon, size: 20),
                  label: Text(section.title),
                  selected: _selected == i,
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
                            children: navigation)),
                    const VerticalDivider(width: 1),
                    content,
                  ])
                : Column(children: [
                    SizedBox(
                        height: 60,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: navigation)),
                    const Divider(height: 1),
                    content,
                  ]));
      });
}
