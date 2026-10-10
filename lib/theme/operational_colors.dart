import 'package:flutter/material.dart';

enum OperationalTone { neutral, information, warning, success, danger }

/// Status text/background pairs, independent of the wine brand accent.
class OperationalColors {
  const OperationalColors(this.foreground, this.background);
  final Color foreground;
  final Color background;

  static OperationalColors of(BuildContext context, OperationalTone tone) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return switch (tone) {
      OperationalTone.information => dark
          ? const OperationalColors(Color(0xFFB9D9FF), Color(0xFF18344F))
          : const OperationalColors(Color(0xFF15558A), Color(0xFFEAF3FF)),
      OperationalTone.warning => dark
          ? const OperationalColors(Color(0xFFFFD795), Color(0xFF49351A))
          : const OperationalColors(Color(0xFF805000), Color(0xFFFFF3DC)),
      OperationalTone.success => dark
          ? const OperationalColors(Color(0xFFADE5C2), Color(0xFF1C3B2B))
          : const OperationalColors(Color(0xFF23613E), Color(0xFFEAF6EE)),
      OperationalTone.danger => OperationalColors(
          theme.colorScheme.onErrorContainer, theme.colorScheme.errorContainer),
      OperationalTone.neutral => OperationalColors(
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.surfaceContainerHigh),
    };
  }
}
