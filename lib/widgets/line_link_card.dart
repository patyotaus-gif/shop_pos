import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/line_service.dart';

class LineLinkCard extends StatefulWidget {
  const LineLinkCard({super.key, required this.onConnected});
  final Future<void> Function() onConnected;
  @override
  State<LineLinkCard> createState() => _LineLinkCardState();
}

class _LineLinkCardState extends State<LineLinkCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false, _checking = false;
  String? _url, _message;
  DateTime? _expires;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_url == null || _checking || !mounted) return;
    if (_expires != null && DateTime.now().isAfter(_expires!)) {
      _timer?.cancel();
      setState(() {
        _url = null;
        _message = 'ลิงก์หมดอายุ กดเชื่อมใหม่ได้';
      });
      return;
    }
    _checking = true;
    try {
      final status = await LineService.linkStatus();
      if (!mounted) return;
      if (status == 'connected') {
        await widget.onConnected();
        if (!mounted) return;
        _timer?.cancel();
        setState(() {
          _url = null;
          _message = 'เชื่อม LINE กับร้านสำเร็จแล้ว';
        });
      } else if (status == 'expired') {
        _timer?.cancel();
        setState(() {
          _url = null;
          _message = 'ลิงก์หมดอายุ กดเชื่อมใหม่ได้';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _message = 'ยังตรวจผลไม่ได้ ตรวจอินเทอร์เน็ตแล้วกดตรวจอีกครั้ง');
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final result = await LineService.startLink();
      if (!mounted) return;
      setState(() {
        _url = result['url'] as String;
        _expires =
            DateTime.fromMillisecondsSinceEpoch(result['expiresAt'] as int);
        _message =
            'เปิด LINE เพิ่มเพื่อนหากยังไม่ได้เพิ่ม แล้วกดส่งข้อความที่เตรียมไว้เพื่อยืนยันร้าน';
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
      await _open();
    } catch (_) {
      if (mounted) {
        setState(
            () => _message = 'เริ่มเชื่อมไม่ได้ กรุณารอสักครู่แล้วลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    try {
      if (!await launchUrl(Uri.parse(_url!),
          mode: LaunchMode.externalApplication)) {
        throw StateError('open');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'เปิด LINE ไม่สำเร็จ ใช้มือถือสแกน QR ด้านล่าง หรือเปิด LINE แล้วลองอีกครั้ง');
      }
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await LineService.cancelLink();
      _timer?.cancel();
      if (mounted) {
        setState(() {
          _url = null;
          _message = 'ยกเลิกลิงก์เชื่อมแล้ว';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'ยกเลิกไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FilledButton.icon(
            onPressed: _busy
                ? null
                : _url == null
                    ? _start
                    : _open,
            icon: const Icon(Icons.link),
            label: Text(_busy
                ? 'กำลังดำเนินการ...'
                : _url == null
                    ? 'เชื่อม LINE กับร้าน'
                    : 'เปิด LINE เพื่อยืนยัน')),
        if (_message != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_message!)),
        if (_url != null) ...[
          const Text(
              'ใช้มือถืออีกเครื่องสแกนเพื่อเชื่อมได้ ลิงก์ใช้ครั้งเดียว หมดอายุใน 10 นาที อย่าส่งต่อให้ผู้อื่น'),
          Center(
              child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: _url!, size: 200))),
          Wrap(children: [
            TextButton(
                onPressed: _check, child: const Text('ตรวจการเชื่อมต่อ')),
            TextButton(
                onPressed: _busy ? null : _cancel,
                child: const Text('ยกเลิกลิงก์'))
          ]),
        ],
      ]);
}
