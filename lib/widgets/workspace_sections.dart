import 'package:flutter/material.dart';

/// Groups related work without losing the state of each section.
class WorkspaceSections extends StatefulWidget {
  const WorkspaceSections(
      {super.key, required this.labels, required this.pages});
  final List<String> labels;
  final List<Widget> pages;

  @override
  State<WorkspaceSections> createState() => _WorkspaceSectionsState();
}

class _WorkspaceSectionsState extends State<WorkspaceSections> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
                children: List.generate(
                    widget.labels.length,
                    (index) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(widget.labels[index]),
                            selected: _selected == index,
                            onSelected: (_) =>
                                setState(() => _selected = index),
                          ),
                        ))),
          ),
          Expanded(
              child: IndexedStack(index: _selected, children: widget.pages)),
        ]),
      );
}
