import 'package:flutter/material.dart';
import '../services/social_auth_service.dart';
import '../utils/operation_error.dart';

class SocialAuthButtons extends StatefulWidget {
  const SocialAuthButtons(
      {super.key,
      this.link = false,
      this.disabled = false,
      this.onSuccess,
      this.authenticate,
      this.onBusyChanged});
  final bool link;
  final bool disabled;
  final VoidCallback? onSuccess;
  final Future<bool> Function(SocialProvider)? authenticate;
  final ValueChanged<bool>? onBusyChanged;
  @override
  State<SocialAuthButtons> createState() => _SocialAuthButtonsState();
}

class _SocialAuthButtonsState extends State<SocialAuthButtons> {
  bool _busy = false;
  String? _message;
  Future<void> _start(SocialProvider provider) async {
    if (_busy || widget.disabled) return;
    if (widget.link) {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: Text('เชื่อมบัญชี ${provider.label}'),
                  content: const Text(
                      'บัญชีที่เลือกจะเข้าสู่ร้านนี้ได้ รวมถึงกรณี Apple ซ่อนอีเมล โปรดเลือกบัญชีของเจ้าของร้านเท่านั้น'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('เชื่อมบัญชี'))
                  ]));
      if (confirm != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final success = await (widget.authenticate?.call(provider) ??
          SocialAuthService.authenticate(provider, link: widget.link));
      if (!mounted) return;
      if (success) {
        if (widget.link) {
          setState(() => _message = 'เชื่อม ${provider.label} กับร้านเดิมแล้ว');
        }
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) setState(() => _message = operationError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final p in SocialProvider.values)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy || widget.disabled ? null : () => _start(p),
                        icon: p == SocialProvider.apple
                            ? const Icon(Icons.apple)
                            : Image.asset('assets/auth/google.png',
                                width: 20, height: 20),
                        label: Text(
                            '${widget.link ? 'เชื่อมบัญชี' : 'ดำเนินการต่อด้วย'} ${p.label}'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                      )),
                if (_busy) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_message!)),
              ]),
        ),
      );
}
