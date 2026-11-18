import 'package:flutter/material.dart';

class ReportPalette {
  static const _light = [
    Color(0xFF405CAB),
    Color(0xFF00796E),
    Color(0xFFB15430),
    Color(0xFF794DB3),
    Color(0xFF00789D),
    Color(0xFF956900),
    Color(0xFFAD4275),
  ];
  static const _dark = [
    Color(0xFFA4B8FF),
    Color(0xFF68D9C1),
    Color(0xFFFBAA84),
    Color(0xFFD0ACFF),
    Color(0xFF7ACFEF),
    Color(0xFFEBC36C),
    Color(0xFFEEA4C6),
  ];

  static Color series(BuildContext context, int index) {
    final palette =
        Theme.of(context).brightness == Brightness.dark ? _dark : _light;
    return palette[index % palette.length];
  }
}
