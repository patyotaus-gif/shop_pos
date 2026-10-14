import 'package:flutter/material.dart';

/// Own the system navigation/gesture inset above the Navigator, so pushed
/// pages and modal routes receive the same protection as the main tabs.
/// SafeArea consumes the padding for descendants, avoiding duplicate gaps.
class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});

  final Widget child;

  static Widget builder(BuildContext context, Widget? child) =>
      AppViewport(child: child ?? const SizedBox.shrink());

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          // App bars and individual pages still own the status-bar inset.
          top: false,
          // Use padding rather than viewPadding: the keyboard replaces the
          // bottom inset, and Scaffold/modal sheets handle viewInsets.
          child: child,
        ),
      );
}
