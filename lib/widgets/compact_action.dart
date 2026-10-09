import 'package:flutter/material.dart';

/// Releases a stretching parent's width while retaining a comfortable tap area.
class CompactAction extends StatelessWidget {
  const CompactAction({super.key, required this.child, this.primary = false});

  final Widget child;
  final bool primary;

  @override
  Widget build(BuildContext context) => Align(
        alignment: primary
            ? AlignmentDirectional.center
            : AlignmentDirectional.centerStart,
        widthFactor: 1,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, minHeight: 48),
          child: primary ? SizedBox(width: 360, child: child) : child,
        ),
      );
}

/// Action groups fit their labels and wrap instead of stretching across a row.
class ActionButtons extends StatelessWidget {
  const ActionButtons({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [for (final child in children) CompactAction(child: child)],
      );
}
