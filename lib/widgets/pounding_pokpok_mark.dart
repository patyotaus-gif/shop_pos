import 'package:flutter/material.dart';

/// Two mortar strikes per loop, using separate layers of the team's artwork.
class PoundingPokpokMark extends StatelessWidget {
  const PoundingPokpokMark({
    super.key,
    required this.progress,
    this.size = 200,
    this.reduceMotion = false,
  });

  final double progress;
  final double size;
  final bool reduceMotion;

  static double _sample(double t, List<double> stops, List<double> values) {
    if (t <= stops.first) return values.first;
    for (var i = 1; i < stops.length; i++) {
      if (t <= stops[i]) {
        final f = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return values[i - 1] + (values[i] - values[i - 1]) * f;
      }
    }
    return values.last;
  }

  @override
  Widget build(BuildContext context) {
    final dy = reduceMotion
        ? 0.0
        : _sample(progress, [0, .10, .19, .26, .35, .41, .48, .70, 1],
            [-64, -64, 80, -32, 80, 16, 0, 0, -64]);
    final squash = reduceMotion
        ? 0.0
        : _sample(progress, [0, .16, .19, .25, .32, .35, .41, 1],
            [0, 0, 1, 0, 0, .7, 0, 0]);
    Widget layer(String name) =>
        Image.asset('assets/icon/splash/white-$name.png',
            width: size, height: size, excludeFromSemantics: true);
    return Semantics(
      label: 'Pokpok',
      image: true,
      child: SizedBox(
        width: size,
        height: size * .84,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            top: 0,
            left: 0,
            width: size,
            height: size,
            child: Transform.translate(
                offset: Offset(0, dy * size / 1024), child: layer('pestle')),
          ),
          Positioned(
            top: 0,
            left: 0,
            width: size,
            height: size,
            child: Transform(
              // Keep the base (y=786 of the source's 1024 units) stationary.
              alignment: const Alignment(0, .53515625),
              transform: Matrix4.diagonal3Values(
                  1 + .025 * squash, 1 - .035 * squash, 1),
              child: layer('bowl'),
            ),
          ),
        ]),
      ),
    );
  }
}
