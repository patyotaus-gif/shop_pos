import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/screens/bluetooth_printer_screen.dart';
import 'package:shop_pos/services/bluetooth_printer_service.dart';
import 'package:shop_pos/utils/esc_pos_raster.dart';

class _RasterPlatform extends PrintingPlatform {
  bool empty = false;
  int height = 1;
  @override
  Stream<PdfRaster> raster(
      Uint8List document, List<int>? pages, double dpi) async* {
    if (!empty) {
      yield PdfRaster(
          384,
          height,
          Uint8List.fromList(
              List.generate(384 * height * 4, (i) => i % 4 == 3 ? 255 : 0)));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config =
      BluetoothPrinterConfig(address: '00:11:22:33:44:55', name: 'Receipt');
  late PrintingPlatform previous;
  late _RasterPlatform platform;
  final calls = <MethodCall>[];
  setUp(() {
    previous = PrintingPlatform.instance;
    platform = _RasterPlatform();
    PrintingPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel,
            (call) async {
      calls.add(call);
      if (call.method == 'pairedDevices') {
        return [
          {'address': config.address, 'name': config.name}
        ];
      }
      return null;
    });
  });
  tearDown(() {
    PrintingPlatform.instance = previous;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, null);
  });

  test('automatic authorization failure sends no Bluetooth bytes', () async {
    await expectLater(
        BluetoothPrinterService.printPdf(Uint8List(1), config,
            beforeSend: () async {
          throw StateError('order cancelled');
        }),
        throwsStateError);
    expect(calls, isEmpty);
    // Rendering/authorization failure releases the per-engine print lock.
    await BluetoothPrinterService.printPdf(Uint8List(1), config);
    expect(calls.map((c) => c.method), ['printBytes']);
  });

  test('raster uses MSB first and alpha compositing on white', () {
    final rgba = Uint8List.fromList([
      0,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      255,
      0,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
    ]);
    expect(EscPosRaster.encodeRgba(rgba, 9, 1),
        [0x1d, 0x76, 0x30, 0, 2, 0, 1, 0, 0x91, 0x80]);
  });
  test('raster bands preserve every row without blank feeds', () {
    final rgba = Uint8List(8 * 65 * 4);
    for (var i = 3; i < rgba.length; i += 4) {
      rgba[i] = 255;
    }
    final bytes = EscPosRaster.encodeRgba(rgba, 8, 65);
    expect(bytes.length, 8 + 64 + 8 + 1);
    expect(bytes.sublist(72, 80), [0x1d, 0x76, 0x30, 0, 1, 0, 1, 0]);
    expect(bytes.last, 255);
    expect(() => EscPosRaster.encodeRgba(Uint8List(4), 577, 1),
        throwsArgumentError);
  });
  test('printer preferences round trip and forget locally', () async {
    expect(await BluetoothPrinterService.saved(), isNull);
    await BluetoothPrinterService.save(const BluetoothPrinterConfig(
        address: '00:11:22:33:44:55', name: 'Receipt', paperMm: 80));
    expect((await BluetoothPrinterService.saved())!.paperMm, 80);
    await BluetoothPrinterService.forget();
    expect(await BluetoothPrinterService.saved(), isNull);
  });
  test('test print creates a Thai PDF for each supported paper width',
      () async {
    for (final width in [58, 80]) {
      final bytes = await BluetoothPrinterService.testDocument(width);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
    }
  });
  test('printing sends one bounded job with init and feed, no cut', () async {
    await BluetoothPrinterService.printPdf(Uint8List.fromList([1]), config);
    expect(calls.map((c) => c.method), ['printBytes']);
    final data = calls.single.arguments as Map;
    expect(data['address'], config.address);
    final bytes = data['bytes'] as Uint8List;
    expect(
        bytes.sublist(0, 10), [0x1b, 0x40, 0x1d, 0x76, 0x30, 0, 48, 0, 1, 0]);
    expect(bytes.sublist(bytes.length - 3), [0x1b, 0x4a, 120]);
    expect(bytes.length, 2 + 8 + 48 + 3);
  });
  test('long raster includes every footer row before the final tear feed',
      () async {
    platform.height = 2049;
    await BluetoothPrinterService.printPdf(Uint8List(1), config);
    final bytes = calls.single.arguments['bytes'] as Uint8List;
    var offset = 2;
    var rows = 0;
    while (offset < bytes.length - 3) {
      expect(bytes.sublist(offset, offset + 4), [0x1d, 0x76, 0x30, 0]);
      final widthBytes = bytes[offset + 4] + bytes[offset + 5] * 256;
      final bandRows = bytes[offset + 6] + bytes[offset + 7] * 256;
      rows += bandRows;
      offset += 8 + widthBytes * bandRows;
    }
    expect(rows, 2049);
    expect(offset, bytes.length - 3);
    expect(bytes[offset - 1], 255); // Last black footer pixel survived.
    expect(bytes.sublist(offset), [0x1b, 0x4a, 120]);
  });
  test('empty PDF and unsupported platform never contact printer', () async {
    platform.empty = true;
    await expectLater(BluetoothPrinterService.printPdf(Uint8List(1), config),
        throwsStateError);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await expectLater(BluetoothPrinterService.printPdf(Uint8List(1), config),
        throwsStateError);
    expect(calls, isEmpty);
  });
  test('transport failure is not retried and releases print lock', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel,
            (call) async {
      attempts++;
      throw PlatformException(
          code: 'print_failed', message: 'ตรวจใบเดิมก่อนลองใหม่');
    });
    for (var i = 0; i < 2; i++) {
      await expectLater(BluetoothPrinterService.printPdf(Uint8List(1), config),
          throwsA(isA<PlatformException>()));
      expect(attempts, i + 1);
    }
  });
  test('concurrent print is rejected rather than interleaving receipt bytes',
      () async {
    final sending = Completer<void>();
    final reached = Completer<void>();
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel,
            (call) async {
      attempts++;
      reached.complete();
      await sending.future;
      return null;
    });
    final first = BluetoothPrinterService.printPdf(Uint8List(1), config);
    await reached.future;
    await expectLater(BluetoothPrinterService.printPdf(Uint8List(1), config),
        throwsStateError);
    expect(attempts, 1);
    sending.complete();
    await first;
  });
  testWidgets(
      'paired device selection fits small phones and saves without printing',
      (tester) async {
    debugDefaultTargetPlatformOverride = null;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: BluetoothPrinterScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Receipt'), findsOneWidget);
    await tester.tap(find.text('Receipt'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ใช้เครื่องนี้'), 180);
    await tester.tap(find.text('ใช้เครื่องนี้'));
    await tester.pumpAndSettle();
    expect((await BluetoothPrinterService.saved())!.address, config.address);
    expect(calls.where((c) => c.method == 'printBytes'), isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('permission denial gives a recoverable error', (tester) async {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BluetoothPrinterService.channel, (_) async {
      throw PlatformException(
          code: 'permission', message: 'กรุณาอนุญาตอุปกรณ์ใกล้เคียง');
    });
    await tester.pumpWidget(const MaterialApp(home: BluetoothPrinterScreen()));
    await tester.pumpAndSettle();
    expect(find.text('กรุณาอนุญาตอุปกรณ์ใกล้เคียง'), findsOneWidget);
    expect(find.text('รีเฟรช'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
