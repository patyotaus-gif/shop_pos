import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/main.dart';
import 'package:shop_pos/services/update_service.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/update_prompt.dart';

final _manifest = <String, dynamic>{
  'version': '1.2.85',
  'build': 102,
  'url': 'https://pok-pok.app/app/pokpok.apk',
  'notes': 'สรุปสำหรับแอปรุ่นเดิม',
  'details': ['ติดตามสถานะการชำระเงิน', 'ยืนยันอีเมลก่อนเข้าร้าน'],
  'sizeBytes': 93116244,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(PokpokTheme.fontFamily)
          ..addFont(rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'))
          ..addFont(
              rootBundle.load('assets/fonts/IBMPlexSansThai-SemiBold.ttf')))
        .load();
  });
  final android =
      AppUpdateInfo.available(_manifest, TargetPlatform.android, 101)!;
  final iosManifest = <String, dynamic>{
    'ios': {
      'version': '1.2.85',
      'build': 8,
      'url': 'https://testflight.apple.com/join/vA1VYAgZ',
      'notes': 'ยืนยันอีเมล',
    }
  };
  final ios = AppUpdateInfo.available(iosManifest, TargetPlatform.iOS, 7)!;

  test('chooses releases for the installed platform and build', () {
    expect(ios.details, ['ยืนยันอีเมล']);
    expect(android.details, _manifest['details']);
    expect(AppUpdateInfo.available(_manifest, TargetPlatform.iOS, 1), isNull);
    expect(AppUpdateInfo.available(_manifest, TargetPlatform.android, 102),
        isNull);
    expect(AppUpdateInfo.available(_manifest, TargetPlatform.android, 103),
        isNull);
    final mandatory = AppUpdateInfo.available(
        {..._manifest, 'minSupportedBuild': 101}, TargetPlatform.android, 100)!;
    expect(mandatory.mandatory, isTrue);
    expect(AppUpdateInfo.available({'ios': _manifest}, TargetPlatform.iOS, 1),
        isNull);
  });

  test('remembers a known release offline and invalidates it after a rollback',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    void installed(int build) => PackageInfo.setMockInitialValues(
        appName: 'Pokpok',
        packageName: 'app.pokpok.pos',
        version: '1.2.84',
        buildNumber: '$build',
        buildSignature: '');
    Future<AppUpdateInfo?> check(Map<String, dynamic>? reply) =>
        http.runWithClient(
          UpdateService.checkForUpdate,
          () => MockClient((request) async {
            expect(
                request.url.toString(), 'https://pok-pok.app/app/version.json');
            if (reply == null) throw http.ClientException('offline');
            return http.Response.bytes(utf8.encode(jsonEncode(reply)), 200);
          }),
        );
    installed(101);
    expect((await check(_manifest))!.details, _manifest['details']);
    expect((await check(null))!.build, 102);
    installed(102);
    expect(await check(null), isNull);
    installed(101);
    expect(await check({..._manifest, 'build': 101}), isNull);
    expect(await check(null), isNull);
  });

  test('downloads complete verified bytes and rejects partial or changed APKs',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('pokpok-update-test-');
    addTearDown(() => directory.delete(recursive: true));
    final info = AppUpdateInfo.available({
      ..._manifest,
      'sizeBytes': 3,
      'sha256':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    }, TargetPlatform.android, 101)!;
    final progress = <double>[];
    Future<String> download(String body) => http.runWithClient(
          () => UpdateService.downloadApk(info, progress.add,
              directory: directory),
          () => MockClient(
              (request) async => http.Response.bytes(utf8.encode(body), 200)),
        );
    final ready = File(await download('abc'));
    expect(await ready.readAsString(), 'abc');
    expect(progress.last, 1);
    await expectLater(download('ab'), throwsFormatException);
    await expectLater(download('abd'), throwsFormatException);
    expect(await ready.readAsString(), 'abc');
    expect(await download('abc'), ready.path);
    expect(await directory.list().length, 1);
  });

  testWidgets(
      'normal app entry reminds before login, after dismissal and until installed',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    int checks = 0;
    AppUpdateInfo? available = android;
    final boot = Completer<void>();
    await tester.pumpWidget(ShopPosApp(
        initialize: () => boot.future,
        checkForUpdate: () async {
          checks++;
          return available;
        }));
    await tester.pumpAndSettle();
    expect(find.text('อัปเดต Pokpok'), findsOneWidget);
    expect(find.text('ยืนยันอีเมลก่อนเข้าร้าน'), findsOneWidget);
    Future<void> reenter() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await reenter();
    expect(find.byType(UpdateDialog), findsOneWidget);
    await tester.tap(find.text('ไว้ครั้งหน้า'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    await reenter();
    expect(find.byType(UpdateDialog), findsOneWidget);
    available = null;
    await reenter();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(checks, 4);
  });

  testWidgets(
      'overlapping entries use the latest check and respect dismissal for this visit',
      (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final navigator = GlobalKey<NavigatorState>();
    final checks = <Completer<AppUpdateInfo?>>[];
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) => AppUpdateReminder(
          navigatorKey: navigator,
          child: child!,
          check: () {
            final check = Completer<AppUpdateInfo?>();
            checks.add(check);
            return check.future;
          }),
      home: const Scaffold(),
    ));
    void resume() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    expect(checks.length, 1);
    resume();
    resume();
    expect(checks.length, 1);
    checks.first.complete(android);
    await tester.pumpAndSettle();
    expect(checks.length, 2);
    expect(find.byType(UpdateDialog), findsNothing);
    checks.last.complete(android);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    resume();
    expect(checks.length, 3);
    await tester.tap(find.text('ไว้ครั้งหน้า'));
    await tester.pumpAndSettle();
    checks.last.complete(android);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(checks.length, 3);
    resume();
    checks.last.complete(android);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(checks.length, 4);
    resume();
    await tester.tap(find.text('ไว้ครั้งหน้า'));
    await tester.pumpAndSettle();
    checks.last.complete(AppUpdateInfo.available(
        {..._manifest, 'mandatory': true}, TargetPlatform.android, 101));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(find.text('ไว้ครั้งหน้า'), findsNothing);
  });

  testWidgets('an open dialog follows revised metadata for the same build',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final manifest = Map<String, dynamic>.from(_manifest);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      builder: (_, child) => AppUpdateReminder(
          navigatorKey: navigator,
          check: () async =>
              AppUpdateInfo.available(manifest, TargetPlatform.android, 101),
          child: child!),
      home: const Scaffold(),
    ));
    await tester.pumpAndSettle();
    final dialog = find.byType(UpdateDialog);
    final initialState = tester.state(dialog);
    Future<void> resume() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await resume();
    expect(tester.state(dialog), same(initialState),
        reason:
            'an unchanged release keeps the active dialog and its download');
    manifest['details'] = ['รายละเอียดที่แก้ไข'];
    await resume();
    expect(find.text('รายละเอียดที่แก้ไข'), findsOneWidget);
    manifest['sha256'] = 'updated-digest';
    await resume();
    expect(tester.widget<UpdateDialog>(dialog).info.sha256, 'updated-digest');
    manifest['url'] = 'https://pok-pok.app/app/new.apk';
    await resume();
    expect(tester.widget<UpdateDialog>(dialog).info.url.path, '/app/new.apk');
    manifest['mandatory'] = true;
    await resume();
    expect(find.text('ไว้ครั้งหน้า'), findsNothing);
  });

  testWidgets(
      'failed or cancelled Android installation stays actionable without downloading twice',
      (tester) async {
    int downloads = 0;
    int opens = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UpdateDialog(
      info: android,
      download: (_, progress) async {
        downloads++;
        progress(1);
        return 'downloaded.apk';
      },
      install: (_, path) async {
        expect(path, 'downloaded.apk');
        if (++opens == 1) throw StateError('permission');
      },
    ))));
    await tester.tap(find.text('อัปเดตเลย'));
    await tester.pumpAndSettle();
    expect(find.textContaining('เปิดตัวติดตั้งไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เปิดตัวติดตั้งอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(downloads, 1);
    expect(opens, 3);
    expect(find.byType(UpdateDialog), findsOneWidget);
  });

  testWidgets('TestFlight opens without an APK download', (tester) async {
    int opens = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UpdateDialog(
      info: ios,
      download: (_, progress) async =>
          throw TestFailure('iOS attempted to download an APK'),
      install: (info, file) async {
        expect(info.url.host, 'testflight.apple.com');
        expect(file, isNull);
        opens++;
      },
    ))));
    await tester.tap(find.text('เปิด TestFlight'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(find.textContaining('แตะอัปเดตใน TestFlight'), findsOneWidget);
  });

  for (final width in [390.0, 768.0, 1440.0]) {
    testWidgets('release information at width $width', (tester) async {
      tester.view.physicalSize = Size(width, width == 390 ? 844 : 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final navigator = GlobalKey<NavigatorState>();
      final info = AppUpdateInfo.available({
        ..._manifest,
        'details': [
          'บัญชีที่สมัครด้วยอีเมลจะได้รับลิงก์ให้ยืนยันก่อนเข้าใช้งานร้าน',
          'ลูกค้าที่ส่งสลิปสามารถดูผลยืนยันการชำระเงินในหน้าเดิมได้',
          'เมื่อบันทึกรับโอนที่เคาน์เตอร์ เลขอ้างอิงจะแสดงในรายละเอียดบิล',
        ]
      }, TargetPlatform.android, 101)!;
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            navigatorKey: navigator,
            theme: PokpokTheme.light(),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => AppUpdateReminder(
                navigatorKey: navigator,
                check: () async => info,
                child: child!),
            home: const Scaffold(),
          )));
      await tester.pumpAndSettle();
      expect(find.text('อัปเดตเลย').hitTestable(), findsOneWidget);
      expect(find.text('ไว้ครั้งหน้า').hitTestable(), findsOneWidget);
      expect(tester.getSize(find.byType(AlertDialog)).width,
          lessThanOrEqualTo(width));
      final path = Platform.environment['POKPOK_UPDATE_CAPTURES'];
      if (path != null) {
        await tester.runAsync(() async {
          final target = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await target.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = await Directory(path).create(recursive: true);
          await File('${dir.path}/update-${width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'long release notes scroll while the update action remains reachable on a small phone',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final info = AppUpdateInfo.available({
      ..._manifest,
      'details': List.generate(
          14,
          (i) =>
              'ส่วนที่ ${i + 1} อ่านรายละเอียดการเปลี่ยนแปลงเวอร์ชันนี้ได้ครบทุกข้อ')
    }, TargetPlatform.android, 101)!;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.dark(),
        home: Scaffold(body: UpdateDialog(info: info))));
    expect(find.text('อัปเดตเลย').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.textContaining('ส่วนที่ 14 '));
    await tester.pumpAndSettle();
    expect(find.textContaining('ส่วนที่ 14 ').hitTestable(), findsOneWidget);
    expect(find.text('อัปเดตเลย').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
