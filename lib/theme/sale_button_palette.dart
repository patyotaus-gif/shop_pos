import 'package:flutter/material.dart';

/// Named, soft category colors. Text/edges use the same high-contrast ink.
/// Category names stay visible: colors are never the only category cue.
abstract final class SaleButtonPalette {
  static const labels = {
    'wine': 'ชมพู',
    'blue': 'ฟ้า',
    'teal': 'เขียวอมฟ้า',
    'amber': 'เหลือง',
    'purple': 'ม่วง',
  };
  static const _light = {
    'wine': Color(0xFFF5E0E4),
    'blue': Color(0xFFDDEAF8),
    'teal': Color(0xFFD9EEEA),
    'amber': Color(0xFFF6EACB),
    'purple': Color(0xFFEAE1F6),
  };
  static const _dark = {
    'wine': Color(0xFF482B32),
    'blue': Color(0xFF253B50),
    'teal': Color(0xFF203E39),
    'amber': Color(0xFF453A22),
    'purple': Color(0xFF3B2E4A),
  };

  static Color background(BuildContext context, String? name) {
    final theme = Theme.of(context);
    return (theme.brightness == Brightness.dark ? _dark : _light)[name] ??
        theme.colorScheme.surface;
  }
}
