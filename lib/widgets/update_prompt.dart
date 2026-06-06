import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Shows the "update available" dialog. For a mandatory update the sheet
/// can't be dismissed until the user updates.
Future<void> showUpdateDialog(BuildContext context, AppUpdateInfo info) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !info.mandatory,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final AppUpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double _progress = 0;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    try {
      final path = await UpdateService.downloadApk(
        widget.info.url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await UpdateService.install(path);
      // The system installer is now in front; close the dialog so the app
      // isn't left blocking behind it.
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'ดาวน์โหลดไม่สำเร็จ ลองใหม่อีกครั้ง หรือเช็กอินเทอร์เน็ต';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return PopScope(
      canPop: !info.mandatory && !_busy,
      child: AlertDialog(
        title: Text('มีอัปเดตใหม่  (v${info.version})'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (info.notes.isNotEmpty)
              Text(info.notes, style: const TextStyle(fontSize: 14, height: 1.5)),
            if (_busy) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 6),
              Text('กำลังดาวน์โหลด ${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(
                      fontSize: 13, color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: _busy
            ? null
            : [
                if (!info.mandatory)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ภายหลัง'),
                  ),
                FilledButton(
                  onPressed: _update,
                  child: Text(_error == null ? 'อัปเดตเลย' : 'ลองอีกครั้ง'),
                ),
              ],
      ),
    );
  }
}
