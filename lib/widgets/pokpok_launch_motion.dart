import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pokpok_brand.dart';
import 'pounding_pokpok_mark.dart';

/// A one-shot foreground overlay. Startup, authentication and navigation keep
/// running underneath, including their existing loading and recovery screens.
class PokpokLaunchMotion extends StatefulWidget {
  const PokpokLaunchMotion({super.key, required this.child, this.createPlayer});
  final Widget child;
  @visibleForTesting
  final AudioPlayer Function()? createPlayer;

  @override
  State<PokpokLaunchMotion> createState() => _PokpokLaunchMotionState();
}

class _PokpokLaunchMotionState extends State<PokpokLaunchMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const duration = Duration(milliseconds: 2180);
  static const _maxAudioPreparation = Duration(milliseconds: 500);
  late final _motion = AnimationController(vsync: this, duration: duration)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _releaseAudio();
    });
  AudioPlayer? _audio;
  Timer? _audioDeadline;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _finish();
    } else {
      _startIfForeground();
    }
  }

  void _startIfForeground() {
    if (_started || !_isForeground) return;
    _started = true;
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      _motion.forward();
      return;
    }
    // Native audio starts at sample zero alongside the 1.5 s intro. Slow
    // devices get a silent intro instead of a late knock or a delayed launch.
    _audioDeadline = Timer(_maxAudioPreparation, () {
      _releaseAudio();
      _motion.forward();
    });
    unawaited(_prepareSoundAndStart());
  }

  bool get _isForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> _prepareSoundAndStart() async {
    try {
      final player = widget.createPlayer?.call() ?? AudioPlayer();
      _audio = player;
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.assistanceSonification,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      if (_audio != player) return;
      await player
          .setSource(AssetSource('icon/splash/pokpok-mortar-knocks.wav'));
      if (_audio != player) return;
      _audioDeadline?.cancel();
      _audioDeadline = null;
      _motion.forward();
      await player.resume();
    } catch (_) {
      // Optional audio can fail independently of the startup flow.
      final waiting = _audioDeadline != null;
      _releaseAudio();
      if (waiting) _motion.forward();
    }
  }

  void _releaseAudio() {
    _audioDeadline?.cancel();
    _audioDeadline = null;
    final player = _audio;
    _audio = null;
    if (player != null) unawaited(player.dispose().catchError((_) {}));
  }

  void _finish() {
    _motion.value = 1;
    _releaseAudio();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startIfForeground();
    } else if (_started && !_motion.isCompleted) {
      _finish();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseAudio();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _motion,
        child: widget.child,
        builder: (context, destination) {
          final active = !_motion.isCompleted;
          final ms = _motion.value * duration.inMilliseconds;
          final intro = (ms / 1500).clamp(0.0, 1.0);
          final wordmarkFraction =
              (const Interval(.25, .42, curve: Curves.easeOut)
                          .transform(intro) +
                      const Interval(.52, .78, curve: Curves.easeOut)
                          .transform(intro)) /
                  2;
          final exit = const Cubic(.45, 0, .25, 1)
              .transform(((ms - 1500) / 680).clamp(0.0, 1.0));
          return Stack(fit: StackFit.expand, children: [
            ExcludeFocus(
                excluding: active,
                child: ExcludeSemantics(
                  excluding: active,
                  child: IgnorePointer(ignoring: active, child: destination),
                )),
            if (active)
              ClipPath(
                clipper: _WaveClip(exit),
                child: Semantics(
                    label: 'กำลังเปิด Pokpok',
                    child: ExcludeSemantics(
                      child: ColoredBox(
                          color: const Color(0xff7a1f2b),
                          child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  PoundingPokpokMark(
                                      size: 146, progress: intro),
                                  SizedBox(
                                      width: 125,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ClipRect(
                                            child: Align(
                                                alignment: Alignment.centerLeft,
                                                widthFactor: wordmarkFraction,
                                                child: const PokpokWordmark(
                                                    width: 125,
                                                    color: Colors.white))),
                                      )),
                                  const SizedBox(height: 6),
                                  Opacity(
                                    opacity: const Interval(.62, 1,
                                            curve: Curves.easeOut)
                                        .transform(intro),
                                    child: const Text('POINT OF SALE',
                                        style: TextStyle(
                                          inherit: false,
                                          fontSize: 10,
                                          height: 1.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                          letterSpacing: 3.5,
                                        )),
                                  ),
                                ]),
                          )),
                    )),
              ),
          ]);
        },
      );
}

class _WaveClip extends CustomClipper<Path> {
  const _WaveClip(this.progress);
  final double progress;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height;
    final x = w * (1 - progress);
    final bend = w * 4 * progress * (1 - progress);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(x, 0)
      ..cubicTo(x + .16 * bend, .19 * h, x - .14 * bend, .29 * h,
          x - .04 * bend, .5 * h)
      ..cubicTo(
          x + .06 * bend, .71 * h, x + .15 * bend, .76 * h, x - .01 * bend, h)
      ..lineTo(0, h)
      ..close();
  }

  @override
  bool shouldReclip(_WaveClip oldClipper) => progress != oldClipper.progress;
}
