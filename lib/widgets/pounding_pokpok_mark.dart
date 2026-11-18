import 'package:flutter/material.dart';

/// Two strikes and two ripples, drawn with the team's transparent logo layers.
class PoundingPokpokMark extends StatelessWidget {
  const PoundingPokpokMark({
    super.key,
    required this.progress,
    this.size = 200,
  });

  final double progress;
  final double size;

  double _sample(List<double> stops, List<double> values) {
    for (var i = 1; i < stops.length; i++) {
      if (progress <= stops[i]) {
        final t = (progress - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return values[i - 1] +
            (values[i] - values[i - 1]) *
                Curves.easeInOut.transform(t.clamp(0, 1));
      }
    }
    return values.last;
  }

  Widget _ripple(double start, double end) {
    final t = Interval(start, end, curve: Curves.easeOut).transform(progress);
    final alpha = t < .16 ? t / .16 : (1 - t) / .84;
    return Positioned(
      left: 0,
      right: 0,
      top: size * .05,
      height: size,
      child: Transform.scale(
        scale: .36 + 1.36 * t,
        child: DecoratedBox(
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: alpha * .32),
                    width: 1.5))),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const strikes = [0.0, .13, .25, .41, .54, .65, .77, 1.0];
    final dy = _sample(strikes, [0, -.13, .09, -.18, .11, -.05, 0, 0]);
    final dx = _sample(strikes, [0, -.03, 0, .04, 0, 0, 0, 0]);
    final angle = _sample(strikes, [0, -.31, .087, .38, -.105, .07, 0, 0]);
    final squash = _sample([0, .21, .25, .38, .49, .54, .64, .79, 1],
        [0, 0, .7, 0, 0, 1, -.3, 0, 0]);
    Widget layer(String name) =>
        Image.asset('assets/icon/splash/white-$name.png',
            width: size, height: size, excludeFromSemantics: true);

    return SizedBox(
      width: size,
      height: size * .84,
      child: Stack(clipBehavior: Clip.none, children: [
        _ripple(.247, .534),
        _ripple(.533, .967),
        Positioned(
            top: 0,
            width: size,
            height: size,
            child: Transform.translate(
                offset: Offset(dx * size, dy * size),
                child: Transform.rotate(
                    angle: angle,
                    alignment: const Alignment(0, -.1),
                    child: layer('pestle')))),
        Positioned(
            top: 0,
            width: size,
            height: size,
            child: Transform(
                alignment: const Alignment(0, .53515625),
                transform: Matrix4.diagonal3Values(
                    1 + .12 * squash, 1 - .16 * squash, 1),
                child: layer('bowl'))),
      ]),
    );
  }
}
