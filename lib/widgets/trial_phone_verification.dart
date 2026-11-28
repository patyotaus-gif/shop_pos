import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'trial_phone_session.dart';

String? normalizeTrialPhone(String input) {
  var number = input.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^0[689]\d{8}$').hasMatch(number)) {
    number = '+66${number.substring(1)}';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(number) ? number : null;
}

String phoneVerificationMessage(String code) => switch (code) {
      'credential-already-in-use' ||
      'account-exists-with-different-credential' =>
        'เบอร์นี้ผูกกับบัญชีอื่นแล้ว กรุณาเข้าด้วยบัญชีเดิมหรือขอให้ทีมติดต่อกลับ',
      'invalid-verification-code' =>
        'รหัสไม่ถูกต้อง กรุณาตรวจ SMS แล้วลองอีกครั้ง',
      'session-expired' ||
      'invalid-verification-id' =>
        'รหัสหมดอายุ กรุณาขอรหัสใหม่',
      'too-many-requests' ||
      'quota-exceeded' =>
        'ยังส่งรหัสเพิ่มไม่ได้ กรุณารอสักครู่แล้วลองอีกครั้ง',
      'invalid-phone-number' => 'กรุณาตรวจเบอร์โทรศัพท์และรหัสประเทศ',
      'requires-recent-login' ||
      'user-mismatch' =>
        'กรุณาเข้าสู่ระบบอีกครั้งด้วยบัญชีเดิมเพื่อยืนยันเบอร์',
      'network-request-failed' =>
        'เชื่อมต่อไม่ได้ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง',
      _ => 'ยังยืนยันเบอร์ไม่ได้ ลองอีกครั้งหรือขอให้ทีมติดต่อกลับ',
    };

class TrialPhoneVerification extends StatefulWidget {
  const TrialPhoneVerification({
    super.key,
    required this.auth,
    required this.uid,
    required this.phone,
    required this.onVerified,
    required this.phoneAuth,
    this.existingShop = false,
  });
  final bool existingShop;
  final FirebaseAuth auth;
  final String uid;
  final TextEditingController phone;
  final ValueChanged<TrialPhoneProof> onVerified;
  final Future<FirebaseAuth> Function() phoneAuth;

  @override
  State<TrialPhoneVerification> createState() => _TrialPhoneVerificationState();
}

class _TrialPhoneVerificationState extends State<TrialPhoneVerification> {
  final _code = TextEditingController();
  String? _verificationId, _requestedNumber, _error;
  int? _resendToken;
  int _attempt = 0;
  bool _requesting = false, _checking = false;
  Timer? _resendCooldown;
  bool _active(int attempt) =>
      mounted &&
      attempt == _attempt &&
      widget.auth.currentUser?.uid == widget.uid;
  @override
  void dispose() {
    _code.dispose();
    _resendCooldown?.cancel();
    super.dispose();
  }

  void _edit() {
    setState(() {
      _attempt++;
      _verificationId = null;
      _requestedNumber = null;
      _resendToken = null;
      _requesting = false;
      _error = null;
      _code.clear();
    });
  }

  Future<void> _verify(
      PhoneAuthCredential credential, String expected, int attempt) async {
    if (!_active(attempt) || _checking) return;
    setState(() {
      _checking = true;
      _requesting = false;
      _error = null;
    });
    try {
      final isolated = await widget.phoneAuth();
      if (!_active(attempt)) return;
      final result = await isolated.signInWithCredential(credential);
      if (!_active(attempt)) return;
      if (result.user?.uid == widget.uid ||
          result.user?.phoneNumber != expected) {
        throw FirebaseAuthException(code: 'user-mismatch');
      }
      final proof = await currentTrialPhoneProof(isolated, widget.uid);
      if (!_active(attempt)) return;
      if (proof == null || proof.number != expected) {
        throw FirebaseAuthException(code: 'session-expired');
      }
      widget.onVerified(proof);
    } on FirebaseAuthException catch (e) {
      if (_active(attempt)) {
        setState(() => _error = phoneVerificationMessage(e.code));
      }
    } catch (_) {
      if (_active(attempt)) {
        setState(() => _error = phoneVerificationMessage('unknown'));
      }
    } finally {
      if (_active(attempt)) setState(() => _checking = false);
    }
  }

  Future<void> _send() async {
    if (_requesting || _checking || _resendCooldown != null) return;
    final number = normalizeTrialPhone(widget.phone.text);
    if (number == null) {
      setState(() =>
          _error = 'กรอกเบอร์มือถือ 10 หลัก หรือเบอร์พร้อมรหัสประเทศ เช่น +66');
      return;
    }
    final auth = widget.auth;
    if (auth.currentUser?.uid != widget.uid) {
      setState(() => _error = phoneVerificationMessage('user-mismatch'));
      return;
    }
    final attempt = ++_attempt;
    final token = _requestedNumber == number ? _resendToken : null;
    setState(() {
      _error = null;
      _requesting = true;
      _requestedNumber = number;
    });
    try {
      // FlutterFire routes iOS reCAPTCHA/APNs callbacks to the default app.
      // Requesting a credential here never signs in or alters the signed-in user.
      await auth.setLanguageCode('th');
      if (!_active(attempt)) return;
      await auth.verifyPhoneNumber(
        phoneNumber: number,
        forceResendingToken: token,
        verificationCompleted: (credential) =>
            _verify(credential, number, attempt),
        verificationFailed: (e) {
          if (!_active(attempt)) return;
          setState(() {
            _error = phoneVerificationMessage(e.code);
            _requesting = false;
          });
        },
        codeSent: (id, resendToken) {
          if (!_active(attempt)) return;
          _resendCooldown?.cancel();
          _resendCooldown = Timer(const Duration(minutes: 1), () {
            if (mounted) setState(() => _resendCooldown = null);
          });
          setState(() {
            _verificationId = id;
            _resendToken = resendToken;
            _requesting = false;
            _code.clear();
          });
        },
        codeAutoRetrievalTimeout: (id) {
          if (!_active(attempt)) return;
          setState(() {
            _verificationId ??= id;
            _requesting = false;
          });
        },
      );
    } on FirebaseAuthException catch (e) {
      if (_active(attempt)) {
        setState(() {
          _error = phoneVerificationMessage(e.code);
          _requesting = false;
        });
      }
    } catch (_) {
      if (_active(attempt)) {
        setState(() {
          _error = phoneVerificationMessage('unknown');
          _requesting = false;
        });
      }
    }
  }

  void _confirm() {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'กรอกรหัส 6 หลักที่ได้รับทาง SMS');
      return;
    }
    _verify(
        PhoneAuthProvider.credential(
            verificationId: _verificationId!, smsCode: code),
        _requestedNumber!,
        _attempt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: widget.phone,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        readOnly: _requestedNumber != null,
        decoration: const InputDecoration(
            labelText: 'เบอร์มือถือเจ้าของร้าน', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 8),
      Semantics(
          liveRegion: _verificationId != null,
          child: Text(_verificationId == null
              ? (widget.existingShop
                  ? 'เมื่อกดส่งรหัส ระบบจะส่งเบอร์ให้ Google เพื่อยืนยันเบอร์ของคุณ'
                  : 'เมื่อกดส่งรหัส ระบบจะส่งเบอร์ให้ Google เพื่อยืนยันตัวตนและป้องกันการใช้สิทธิ์ซ้ำ')
              : 'ส่งรหัสแล้ว กรอกรหัส 6 หลักจาก SMS')),
      if (_verificationId != null) ...[
        const SizedBox(height: 16),
        TextFormField(
          controller: _code,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6)
          ],
          decoration: const InputDecoration(
              labelText: 'รหัส OTP 6 หลัก', border: OutlineInputBorder()),
          onFieldSubmitted: (_) => _confirm(),
        ),
      ],
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)))),
      const SizedBox(height: 16),
      if (_verificationId == null)
        FilledButton(
            onPressed: _requesting || _checking || _resendCooldown != null
                ? null
                : _send,
            child: Text(_requesting ? 'กำลังส่งรหัส…' : 'ส่งรหัส OTP'))
      else ...[
        FilledButton(
            onPressed: _checking || _requesting ? null : _confirm,
            child: Text(_checking ? 'กำลังยืนยัน…' : 'ยืนยันรหัส')),
        TextButton(
            onPressed: _resendCooldown == null && !_requesting && !_checking
                ? _send
                : null,
            child: Text(_resendCooldown == null
                ? 'ส่งรหัสอีกครั้ง'
                : 'ส่งรหัสอีกครั้งได้ใน 1 นาที')),
      ],
      if (_requestedNumber != null)
        TextButton(
            onPressed: _checking ? null : _edit,
            child: const Text('แก้ไขเบอร์โทรศัพท์')),
    ]);
  }
}
