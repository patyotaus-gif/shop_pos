import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Owns one reminder above every entry point, including sign-in, staff and
/// offline mode. Dismissing a reminder only lasts for this visit.
class AppUpdateReminder extends StatefulWidget {
  const AppUpdateReminder({
    super.key,
    required this.navigatorKey,
    required this.child,
    this.check = UpdateService.checkForUpdate,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final Future<AppUpdateInfo?> Function() check;

  @override
  State<AppUpdateReminder> createState() => _AppUpdateReminderState();
}

class _AppUpdateReminderState extends State<AppUpdateReminder>
    with WidgetsBindingObserver {
  DialogRoute<void>? _dialog;
  AppUpdateInfo? _displayed;
  bool _checking = false;
  int _visit = 0;
  int? _dismissedVisit;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _visit++;
      unawaited(_check());
    }
  }

  bool get _foreground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  Future<void> _check() async {
    if (!mounted || _checking || !_foreground) return;
    _checking = true;
    final visit = _visit;
    try {
      final info = await widget.check();
      if (!mounted ||
          !_foreground ||
          visit != _visit ||
          (_dismissedVisit == visit && info?.mandatory != true)) {
        return;
      }
      final nav = widget.navigatorKey.currentState;
      final overlay = nav?.overlay;
      if (nav == null || overlay == null) return;
      if (_dialog?.isActive == true) {
        if (info != null && info.matches(_displayed)) return;
        final previous = _dialog!;
        _dialog = null;
        _displayed = null;
        nav.removeRoute(previous);
      }
      if (info == null) return;
      final route = DialogRoute<void>(
        context: overlay.context,
        barrierDismissible: !info.mandatory,
        builder: (_) => UpdateDialog(info: info),
      );
      _dialog = route;
      _displayed = info;
      unawaited(nav.push(route).whenComplete(() {
        if (identical(_dialog, route)) {
          _dialog = null;
          _displayed = null;
          _dismissedVisit = _visit;
        }
      }));
    } finally {
      _checking = false;
      // Coalesce every entry during this request into one fresh manifest read.
      if (mounted && _foreground && _visit != visit) unawaited(_check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.info,
    this.download = UpdateService.downloadApk,
    this.install = UpdateService.install,
  });
  final AppUpdateInfo info;
  final Future<String> Function(AppUpdateInfo, ValueChanged<double>) download;
  final Future<void> Function(AppUpdateInfo, String?) install;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _busy = false;
  bool _openedInstaller = false;
  double? _progress;
  String? _downloaded;
  String? _error;
  final _statusKey = GlobalKey();

  bool get _isAndroid => widget.info.platform == TargetPlatform.android;

  Future<void> _update() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    try {
      if (_isAndroid && _downloaded == null) {
        _downloaded = await widget.download(widget.info, (p) {
          if (mounted) setState(() => _progress = p);
        });
      }
      if (!mounted || ModalRoute.of(context)?.isActive == false) return;
      await widget.install(widget.info, _downloaded);
      // Opening an installer is not a completed update. Keep the prompt ready
      // behind it if the owner cancels or returns from system settings.
      if (mounted) setState(() => _openedInstaller = true);
    } catch (e) {
      if (!mounted) return;
      final failedDownload = _isAndroid && _downloaded == null;
      if (e is FileSystemException) _downloaded = null;
      setState(() => _error = failedDownload
          ? 'ดาวน์โหลดไฟล์อัปเดตไม่สำเร็จ ตรวจการเชื่อมต่อและพื้นที่ว่าง แล้วลองอีกครั้ง'
          : _isAndroid
              ? 'เปิดตัวติดตั้งไม่สำเร็จ ตรวจสิทธิ์ติดตั้งแอปของ Pokpok ในการตั้งค่า Android แล้วลองอีกครั้ง'
              : 'เปิด TestFlight ไม่สำเร็จ ตรวจว่าเครื่องนี้ติดตั้ง TestFlight แล้วลองอีกครั้ง');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final status = _statusKey.currentContext;
          if (status != null) Scrollable.ensureVisible(status);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final theme = Theme.of(context);
    final size = info.sizeBytes;
    final versionText = 'เวอร์ชัน ${info.version} (บิลด์ ${info.build})';
    return PopScope(
      canPop: !info.mandatory && !_busy,
      child: AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        constraints: const BoxConstraints(maxWidth: 540),
        title: const Text('อัปเดต Pokpok'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(versionText, style: theme.textTheme.titleMedium),
            if (_isAndroid && size != null && size > 0)
              Text('ขนาดไฟล์ ${(size / 1000000).toStringAsFixed(1)} MB',
                  style: theme.textTheme.bodySmall),
            if (info.details.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('สิ่งที่เปลี่ยนในเวอร์ชันนี้',
                  style: theme.textTheme.titleSmall),
              for (final item in info.details)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExcludeSemantics(child: Text('•  ')),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
            ],
            if (info.mandatory) ...[
              const SizedBox(height: 12),
              const Text('กรุณาติดตั้งเวอร์ชันนี้เพื่อใช้งาน Pokpok ต่อ'),
            ],
            if (_error != null || _openedInstaller) ...[
              const SizedBox(height: 12),
              Semantics(
                key: _statusKey,
                liveRegion: true,
                child: Text(
                  _error ??
                      (_isAndroid
                          ? 'ยืนยันการติดตั้งในหน้าต่างของ Android หากยกเลิก สามารถเปิดตัวติดตั้งอีกครั้งได้'
                          : 'แตะอัปเดตใน TestFlight แล้วกลับมาเปิด Pokpok'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: _error == null ? null : theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_busy)
            Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_isAndroid && _downloaded == null
                  ? 'กำลังดาวน์โหลด${_progress == null ? '' : ' ${(_progress! * 100).round()}%'}'
                  : _isAndroid
                      ? 'กำลังเปิดตัวติดตั้ง'
                      : 'กำลังเปิด TestFlight'),
            ])
          else ...[
            if (!info.mandatory)
              OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ไว้ครั้งหน้า')),
            FilledButton(
              onPressed: _update,
              child: Text(_error != null
                  ? 'ลองอีกครั้ง'
                  : !_isAndroid
                      ? 'เปิด TestFlight'
                      : _openedInstaller
                          ? 'เปิดตัวติดตั้งอีกครั้ง'
                          : 'อัปเดตเลย'),
            ),
          ],
        ],
      ),
    );
  }
}
