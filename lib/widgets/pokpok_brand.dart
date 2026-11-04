import 'package:flutter/material.dart';

/// The product icon supplied by the design team, rendered from the source SVG.
class PokpokMark extends StatelessWidget {
  const PokpokMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .18),
        child: Image.asset('assets/icon/icon.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            semanticLabel: 'Pokpok'),
      );
}

/// Company identity belongs in product information, separate from shop logos.
void showPokpokAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: 'Pokpok',
    applicationIcon: const PokpokMark(size: 48),
    children: [
      const Text('พัฒนาโดย PEXON INNOVATION'),
      const SizedBox(height: 12),
      Center(
        child: Image.asset('assets/brand/source/pexon-white.png',
            width: 160,
            height: 226,
            fit: BoxFit.contain,
            semanticLabel: 'PEXON INNOVATION'),
      ),
    ],
  );
}
