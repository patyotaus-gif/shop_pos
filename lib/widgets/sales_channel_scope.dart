import 'package:flutter/material.dart';

/// Return to the chooser without disposing the workflow's cart.
class SalesChannelScope extends InheritedWidget {
  const SalesChannelScope(
      {super.key, required this.choose, required super.child});
  final VoidCallback choose;
  static VoidCallback? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SalesChannelScope>()?.choose;
  @override
  bool updateShouldNotify(SalesChannelScope oldWidget) =>
      choose != oldWidget.choose;
}

class SalesChannelBackButton extends StatelessWidget {
  const SalesChannelBackButton({super.key, this.enabled = true});
  final bool enabled;
  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: 'เลือกประเภทการขาย',
      onPressed: enabled ? SalesChannelScope.of(context) : null,
      icon: const Icon(Icons.arrow_back));
}
