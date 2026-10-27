import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/owner_unlock_service.dart';
import '../utils/operation_error.dart';

/// Setup and unlock use the same small-screen form. Callbacks permit exercising
/// rejected PINs and canceled navigation without a real authentication session.
class OwnerPinScreen extends StatefulWidget {
  const OwnerPinScreen({super.key, this.setup = false, this.submit});
  final bool setup;
  final Future<void> Function(String)? submit;
  @override
  State<OwnerPinScreen> createState() => _OwnerPinScreenState();
}

class _OwnerPinScreenState extends State<OwnerPinScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!RegExp(r'^[0-9]{6,8}$').hasMatch(_pin.text)) {
      setState(() => _error = 'กรุณากรอก PIN 6–8 หลัก');
      return;
    }
    if (widget.setup && _pin.text != _confirm.text) {
      setState(() => _error = 'PIN ทั้งสองช่องไม่ตรงกัน');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.submit ??
          (widget.setup
              ? OwnerUnlockService.setup
              : OwnerUnlockService.unlock))(_pin.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FirebaseFunctionsException &&
                ['permission-denied', 'resource-exhausted', 'unauthenticated']
                    .contains(e.code)
            ? (e.message ?? 'ตรวจ PIN ไม่สำเร็จ กรุณาใช้บัญชีเจ้าของร้าน')
            : operationError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label) => TextField(
        controller: controller,
        obscureText: true,
        enabled: !_busy,
        enableSuggestions: false,
        autocorrect: false,
        maxLength: 8,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label),
        onSubmitted: (_) => _submit(),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
              title:
                  Text(widget.setup ? 'ตั้ง PIN เจ้าของ' : 'เข้าโหมดเจ้าของ')),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
            Text(widget.setup
                ? 'ใช้ PIN นี้กลับเข้าโหมดเจ้าของบนเครื่องนี้ อายุ 90 วัน ต้องตั้งค่าหลังล็อกอินด้วยอีเมล / Google / Apple ภายใน 10 นาที'
                : 'กรอก PIN เจ้าของที่ตั้งไว้บนเครื่องนี้'),
            if (widget.setup)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                    'ตั้ง PIN ต่างจากพนักงานและเก็บเป็นความลับ ใครรู้ PIN นี้และใช้เครื่องนี้จะเข้าถึงสิทธิ์เจ้าของได้'),
              ),
            const SizedBox(height: 20),
            _field(_pin, 'PIN เจ้าของ 6–8 หลัก'),
            if (widget.setup) _field(_confirm, 'ยืนยัน PIN เจ้าของ'),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy
                    ? 'กำลังตรวจสอบ…'
                    : widget.setup
                        ? 'บันทึก PIN'
                        : 'เข้าโหมดเจ้าของ')),
            if (!widget.setup)
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('ลืม PIN / ใช้บัญชีเจ้าของแทน')),
          ])),
        ),
      );
}

class OwnerPinSettingsTile extends StatefulWidget {
  const OwnerPinSettingsTile({super.key, this.onChanged});
  final VoidCallback? onChanged;
  @override
  State<OwnerPinSettingsTile> createState() => _OwnerPinSettingsTileState();
}

class _OwnerPinSettingsTileState extends State<OwnerPinSettingsTile> {
  late Future<bool> _enabled = OwnerUnlockService.available();
  bool _busy = false;
  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await OwnerUnlockService.disable();
      widget.onChanged?.call();
      if (mounted) setState(() => _enabled = OwnerUnlockService.available());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!OwnerUnlockService.supported) return const SizedBox.shrink();
    return FutureBuilder<bool>(
        future: _enabled,
        builder: (context, snap) => Column(children: [
              ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('PIN เจ้าของบนเครื่องนี้'),
                  subtitle: Text(snap.data == true
                      ? 'ตั้งค่าไว้แล้ว • แตะเพื่อตั้งใหม่'
                      : 'สลับกลับเข้าเจ้าของโดยไม่ต้องเลือกบัญชีใหม่'),
                  onTap: _busy
                      ? null
                      : () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const OwnerPinScreen(setup: true)));
                          if (mounted) {
                            setState(() =>
                                _enabled = OwnerUnlockService.available());
                            widget.onChanged?.call();
                          }
                        }),
              if (snap.data == true)
                TextButton(
                    onPressed: _busy ? null : _disable,
                    child: const Text('ยกเลิก PIN เจ้าของบนเครื่องนี้')),
            ]));
  }
}
