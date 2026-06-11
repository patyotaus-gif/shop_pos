import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Small "เวอร์ชัน X.Y.Z (build N)" label. Reads the running build via
/// package_info_plus so it always matches what's actually installed.
class AppVersionText extends StatelessWidget {
  const AppVersionText({super.key, this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = style ??
        TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.45));
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        return Text(
          info == null
              ? ''
              : 'เวอร์ชัน ${info.version} (build ${info.buildNumber})',
          textAlign: TextAlign.center,
          style: base,
        );
      },
    );
  }
}
