import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/shop_service.dart';
import 'trial_phone_session.dart';
import 'trial_phone_verification.dart';

class MerchantPhoneGate extends StatefulWidget {
  const MerchantPhoneGate({
    super.key,
    required this.ownerId,
    required this.quickUnlock,
    required this.child,
    this.readStatus = ShopService.merchantPhoneStatus,
    this.verify = ShopService.verifyMerchantPhone,
    this.auth,
    this.phoneAuthFactory = ownerScopedTrialAuth,
  });

  final String ownerId;
  final bool quickUnlock;
  final Widget child;
  final Future<String> Function(String) readStatus;
  final Future<void> Function(String, String) verify;
  final FirebaseAuth? auth;
  final TrialPhoneAuthFactory phoneAuthFactory;

  @override
  State<MerchantPhoneGate> createState() => _MerchantPhoneGateState();
}

class _MerchantPhoneGateState extends State<MerchantPhoneGate> {
  late Future<String> _status = widget.readStatus(widget.ownerId);
  final _number = TextEditingController();
  FirebaseAuth? _isolatedAuth;
  TrialPhoneProof? _proof;
  bool _saving = false;
  String? _error;

  FirebaseAuth get _auth => widget.auth ?? FirebaseAuth.instance;
  Future<FirebaseAuth> _phoneAuth() async =>
      _isolatedAuth ??= await widget.phoneAuthFactory(_auth, widget.ownerId);
  void _refresh() {
    final status = widget.readStatus(widget.ownerId);
    setState(() {
      _status = status;
    });
  }

  Future<void> _save(TrialPhoneProof proof) async {
    if (_saving || _auth.currentUser?.uid != widget.ownerId) return;
    setState(() {
      _saving = true;
      _error = null;
      _proof = proof;
    });
    try {
      await widget.verify(widget.ownerId, proof.token);
      if (!mounted || _auth.currentUser?.uid != widget.ownerId) return;
      _refresh();
      // Verification is already recorded even if local SMS session cleanup fails.
      try {
        await _isolatedAuth?.signOut();
      } on FirebaseAuthException {
        // This secondary session cannot open the merchant workspace.
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.details is Map && e.details['reason'] == 'phone-proof-required') {
          _proof = null;
        }
        _error = e.message?.contains(RegExp('[ก-๙]')) == true
            ? e.message
            : 'ยังบันทึกการยืนยันไม่ได้ กรุณาลองอีกครั้ง';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _status,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snap.data == 'verified') return widget.child;
          final required = snap.data == 'required';
          final theme = Theme.of(context);
          return Scaffold(
            appBar: AppBar(title: const Text('ยืนยันเบอร์เจ้าของร้าน')),
            body: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          required
                              ? 'ยืนยันเบอร์มือถือก่อนขอเพิ่มสาขา'
                              : 'ยังตรวจสอบการยืนยันเบอร์ไม่ได้',
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      if (!required) ...[
                        const Text(
                            'กรุณาตรวจการเชื่อมต่ออินเทอร์เน็ตแล้วลองอีกครั้ง'),
                        FilledButton(
                            onPressed: _refresh,
                            child: const Text('ลองอีกครั้ง')),
                      ] else if (widget.quickUnlock) ...[
                        const Text(
                            'กรุณาออกจากระบบแล้วเข้าด้วยอีเมล Google หรือ Apple ของเจ้าของร้าน เพื่อยืนยันเบอร์ครั้งแรก'),
                      ] else ...[
                        const Text(
                            'เบอร์ของเจ้าของร้านยังไม่ได้รับการยืนยัน กรุณายืนยันด้วยรหัสจาก SMS หนึ่งครั้งเพื่อส่งคำขอและติดตามสาขาของร้าน'),
                        const SizedBox(height: 20),
                        if (_saving)
                          const LinearProgressIndicator(
                              semanticsLabel: 'กำลังบันทึกการยืนยัน')
                        else if (_proof != null &&
                            freshTrialPhoneProof(_proof!))
                          FilledButton(
                              onPressed: () => _save(_proof!),
                              child: const Text('ลองบันทึกการยืนยันอีกครั้ง'))
                        else
                          TrialPhoneVerification(
                            existingShop: true,
                            auth: _auth,
                            uid: widget.ownerId,
                            phone: _number,
                            phoneAuth: _phoneAuth,
                            onVerified: _save,
                          ),
                        if (_error != null)
                          Semantics(
                              liveRegion: true,
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: theme.colorScheme.error))),
                      ],
                      if (widget.quickUnlock)
                        TextButton(
                            onPressed: () async {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                              await AuthService.signOut();
                            },
                            child: const Text('ออกจากระบบ')),
                    ]),
              ),
            ))),
          );
        },
      );
}
