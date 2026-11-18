import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/main.dart' show ShopPosApp;
import 'package:shop_pos/screens/product_form_screen.dart';
import 'package:shop_pos/widgets/pokpok_launch_motion.dart';
import 'package:shop_pos/widgets/pounding_pokpok_mark.dart';

class _DelayedAudio extends Fake implements AudioPlayer {
  final prepared = Completer<void>();
  final playbackAcknowledged = Completer<void>();
  int plays = 0;
  int releases = 0;

  @override
  Future<void> setAudioContext(AudioContext context) async {}
  @override
  Future<void> setSource(Source source) => prepared.future;
  @override
  Future<void> resume() {
    plays++;
    return playbackAcknowledged.future;
  }

  @override
  Future<void> dispose() async => releases++;
}

void main() {
  Widget launch(Widget child,
          {bool reduce = false, AudioPlayer Function()? createPlayer}) =>
      MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child:
                PokpokLaunchMotion(createPlayer: createPlayer, child: child)),
      );
  final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets('wave reveals the existing interactive destination once',
      (tester) async {
    int taps = 0;
    final destination =
        TextButton(onPressed: () => taps++, child: const Text('Shop'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(launch(destination));
    await tester.pump(const Duration(milliseconds: 1500));
    final region = find
        .ancestor(
            of: find.byType(PoundingPokpokMark),
            matching: find.byType(ClipPath))
        .first;
    final frame = tester.getSize(region);
    double visibleWidth() => tester
        .widget<ClipPath>(region)
        .clipper!
        .getClip(frame)
        .getBounds()
        .right;
    expect(visibleWidth(), greaterThanOrEqualTo(frame.width));
    await tester.pump(const Duration(milliseconds: 340));
    expect(visibleWidth(), inExclusiveRange(0, frame.width));
    await tester.tap(find.text('Shop'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pump(const Duration(milliseconds: 341));
    expect(find.byType(PoundingPokpokMark), findsNothing);
    await tester.tap(find.text('Shop'));
    expect(taps, 1);
    await tester.pumpWidget(launch(destination));
    expect(find.byType(PoundingPokpokMark), findsNothing);
  }, variant: desktop);

  testWidgets('reduced motion exposes destination immediately', (tester) async {
    await tester.pumpWidget(launch(const Text('Login'), reduce: true));
    expect(find.byType(PoundingPokpokMark), findsNothing);
    expect(find.text('Login'), findsOneWidget);
  }, variant: desktop);

  testWidgets('first resume starts the motion; interruption finishes it once',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(launch(const Text('Login')));
    await tester.pump(const Duration(milliseconds: 400));
    double progress() => tester
        .widget<PoundingPokpokMark>(find.byType(PoundingPokpokMark))
        .progress;
    expect(progress(), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(progress(), greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(PoundingPokpokMark), findsNothing);
    expect(find.text('Login'), findsOneWidget);
  }, variant: desktop);

  testWidgets('cold-start named route stays behind bootstrap and owner checks',
      (tester) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/product-form';
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final boot = Completer<void>();
    int starts = 0;
    await tester.pumpWidget(ShopPosApp(initialize: () {
      starts++;
      return boot.future;
    }));
    await tester.pumpAndSettle();
    expect(find.byType(ProductFormScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('กำลังเปิดแอป'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed('/');
    await tester.pumpAndSettle();
    expect(starts, 1);
    boot.completeError(StateError('boot failed'));
    await tester.pumpAndSettle();
    expect(find.text('Pokpok POS — startup failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  for (final readyInTime in [true, false]) {
    testWidgets('native audio readiness within deadline: $readyInTime',
        (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final player = _DelayedAudio();
      await tester
          .pumpWidget(launch(const Text('Shop'), createPlayer: () => player));
      await tester.pump(const Duration(milliseconds: 420));
      double progress() => tester
          .widget<PoundingPokpokMark>(find.byType(PoundingPokpokMark))
          .progress;
      expect(progress(), 0);
      if (!readyInTime) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(player.releases, 1);
      }
      player.prepared.complete();
      await tester.pump();
      expect(player.plays, readyInTime ? 1 : 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(progress(), greaterThan(0));
      player.playbackAcknowledged.complete();
      await tester.pump(const Duration(milliseconds: 2180));
      expect(find.byType(PoundingPokpokMark), findsNothing);
      expect(player.releases, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('immediate bootstrap errors reach the recovery screen',
      (tester) async {
    await tester
        .pumpWidget(ShopPosApp(initialize: () => throw StateError('boot')));
    await tester.pumpAndSettle();
    expect(find.text('Pokpok POS — startup failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: desktop);
}
