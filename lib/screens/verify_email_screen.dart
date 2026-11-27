import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.user, this.auth});
  final User user;
  final FirebaseAuth? auth;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  bool _autoSendPending = true;
  bool _needsOwnerLogin = false;
  DateTime? _lastSent;
  String _message = '';
  Timer? _cooldown;
  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  bool get _current => mounted && _auth.currentUser?.uid == widget.user.uid;
  String get _key =>
      'verification-sent-${widget.user.uid}-${widget.user.email}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(sendAutomatically: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldown?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _startCooldown(Duration duration) {
    _cooldown?.cancel();
    _cooldown = Timer(duration, () {
      if (mounted) setState(() => _cooldown = null);
    });
  }

  Future<void> _check(
      {bool sendAutomatically = false, bool resend = false}) async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      await widget.user.reload();
      if (!_current) return;
      final user = _auth.currentUser!;
      // Checking an existing session first avoids emailing someone who already
      // followed their link on a different device.
      final token = await user.getIdTokenResult(user.emailVerified);
      if (!_current || AuthService.acceptsOwnerToken(token.claims ?? {})) {
        return;
      }
      final claims = token.claims;
      if (claims?['ownerQuickUnlock'] == true &&
          claims?['firebase']?['sign_in_provider'] == 'custom' &&
          (user.providerData.isEmpty ||
              user.providerData.any((p) =>
                  const ['google.com', 'apple.com'].contains(p.providerId)))) {
        // An old PIN token predates the server's social-provider proof. A new
        // sign-in proves that identity without mailing the OAuth address.
        _needsOwnerLogin = true;
        _message =
            'กรุณาเข้าสู่ระบบด้วยบัญชีเดิมที่ใช้สมัคร เช่น Google หรือ Apple เพื่อเปิดร้านและใช้ PIN เจ้าของต่อ';
        return;
      }
      if (user.email?.isNotEmpty != true) {
        _message =
            'บัญชีนี้ไม่มีอีเมลสำหรับรับลิงก์ กรุณาเข้าสู่ระบบอีกครั้งด้วยบัญชีเดิมของร้าน';
        return;
      }
      if (!sendAutomatically && !resend && !_autoSendPending) {
        _message =
            'ยังไม่พบการยืนยัน กรุณากดลิงก์ในอีเมลล่าสุด แล้วกลับมาตรวจอีกครั้ง';
        return;
      }
      if (_autoSendPending && _cooldown != null) {
        _message = 'ขอลิงก์หลายครั้งเกินไป กรุณารอสักครู่ก่อนลองใหม่';
        return;
      }
      SharedPreferences? prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {
        // The in-session cooldown also works if local preferences are unavailable.
      }
      if (!_current) return;
      final now = DateTime.now();
      final last = _lastSent ??
          DateTime.fromMillisecondsSinceEpoch(prefs?.getInt(_key) ?? 0);
      final age = now.difference(last);
      if (!age.isNegative && age < const Duration(minutes: 1)) {
        _startCooldown(const Duration(minutes: 1) - age);
      }
      if (!age.isNegative &&
          age <
              (resend ? const Duration(minutes: 1) : const Duration(days: 1))) {
        _autoSendPending = false;
        _message = 'ส่งลิงก์ยืนยันแล้ว หากยังไม่เห็นอีเมล โปรดตรวจโฟลเดอร์สแปม';
        return;
      }
      await _auth.setLanguageCode('th');
      if (!_current) return;
      await user.sendEmailVerification();
      _autoSendPending = false;
      _lastSent = DateTime.now();
      try {
        await prefs?.setInt(_key, _lastSent!.millisecondsSinceEpoch);
      } catch (_) {
        // The email has already been accepted by Firebase.
      }
      if (!_current) return;
      _startCooldown(const Duration(minutes: 1));
      _message = 'ส่งลิงก์ยืนยันแล้ว หากยังไม่เห็นอีเมล โปรดตรวจโฟลเดอร์สแปม';
    } on FirebaseAuthException catch (e) {
      if (_current && e.code == 'too-many-requests') {
        _startCooldown(const Duration(minutes: 1));
        _message = 'ขอลิงก์หลายครั้งเกินไป กรุณารอสักครู่ก่อนลองใหม่';
      } else {
        _message =
            'ติดต่อระบบยืนยันอีเมลไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง';
      }
    } catch (_) {
      _message = 'ติดต่อระบบยืนยันอีเมลไม่สำเร็จ กรุณาลองอีกครั้ง';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                      _needsOwnerLogin
                          ? 'เข้าสู่ระบบเจ้าของร้านอีกครั้ง'
                          : 'ยืนยันอีเมลเพื่อเข้าร้าน',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  if (!_needsOwnerLogin)
                    const Text(
                        'เปิดอีเมลจาก Pokpok แล้วกดลิงก์ยืนยัน จากนั้นกลับมาที่แอป'),
                  const SizedBox(height: 8),
                  SelectableText(widget.user.email ?? ''),
                  const SizedBox(height: 16),
                  Semantics(
                      liveRegion: true,
                      child: Text(_busy ? 'กำลังตรวจสอบ…' : _message)),
                  const SizedBox(height: 20),
                  if (!_needsOwnerLogin)
                    FilledButton(
                        onPressed: _busy ? null : () => _check(),
                        child: const Text('กดลิงก์แล้ว ตรวจสอบอีกครั้ง')),
                  if (!_needsOwnerLogin)
                    OutlinedButton(
                        onPressed: _busy || _cooldown != null
                            ? null
                            : () => _check(resend: true),
                        child: const Text('ส่งอีเมลยืนยันอีกครั้ง')),
                  if (_needsOwnerLogin)
                    FilledButton(
                        onPressed: () =>
                            AuthService.signOut(forgetOwnerDevice: false),
                        child: const Text('กลับไปเข้าสู่ระบบ'))
                  else
                    TextButton(
                        onPressed: AuthService.signOut,
                        child: const Text('ออกจากระบบ / ใช้บัญชีอื่น')),
                ],
              ),
            ),
          ),
        ),
      );
}
