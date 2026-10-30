import 'package:flutter/material.dart';
import 'content_width.dart';

/// Keep document tools reachable without stretching a narrow slip to a tablet.
class DocumentWorkspace extends StatelessWidget {
  const DocumentWorkspace({
    super.key,
    required this.controls,
    required this.preview,
    required this.footer,
  });

  final List<Widget> controls;
  final Widget preview;
  final Widget footer;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: 1120,
          child: Column(children: [
            Expanded(child: LayoutBuilder(builder: (context, constraints) {
              final tools = ListView(
                key: const PageStorageKey('document-tools'),
                padding: const EdgeInsets.all(12),
                children: controls,
              );
              if (constraints.maxWidth >= 840 &&
                  constraints.maxHeight >= 360 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 21) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 320, child: tools),
                      const VerticalDivider(width: 1),
                      Expanded(child: preview),
                    ]);
              }
              return Column(children: [
                SizedBox(
                  height: (constraints.maxHeight * .42).clamp(0, 260),
                  child: tools,
                ),
                const Divider(height: 1),
                Expanded(child: preview),
              ]);
            })),
            Padding(padding: const EdgeInsets.all(12), child: footer),
          ]),
        ),
      );
}
