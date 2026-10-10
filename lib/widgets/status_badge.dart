import 'package:flutter/material.dart';
import '../theme/operational_colors.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(
      {super.key, required this.label, required this.tone, required this.icon});
  final String label;
  final OperationalTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = OperationalColors.of(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: colors.background, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: colors.foreground),
        const SizedBox(width: 6),
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: colors.foreground))),
      ]),
    );
  }
}
