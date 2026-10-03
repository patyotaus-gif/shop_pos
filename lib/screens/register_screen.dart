import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/shop_service.dart';
import '../widgets/tier_picker.dart';
import '../widgets/social_auth_buttons.dart';

/// Version of the Terms/Privacy the signup flow currently presents. Bump
/// this whenever the policy pages change so re-consent can be required.
const kPolicyVersion = '2026-06-07';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.completeProfile = false});
  final bool completeProfile;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  ShopType _shopType = ShopType.retail;
  ShopTier _tier = ShopTier.full; // mass-market default
  bool _loading = false;
  bool _obscure = true;
  bool _acceptedTerms = false;
  String? _error;
  bool _accountCreated = false;
  bool _emailChosen = false;
  bool _shopStep = false;
  final _scroll = ScrollController();
  void _nextStep() {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _shopStep = true;
      _error = null;
    });
    _scroll.jumpTo(0);
  }

  late final _termsTap = TapGestureRecognizer()
    ..onTap = () => _open('https://pok-pok.app/terms');
  late final _privacyTap = TapGestureRecognizer()
    ..onTap = () => _open('https://pok-pok.app/privacy');

  @override
  void dispose() {
    _scroll.dispose();
    _shopNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _referralCtrl.dispose();
    _termsTap.dispose();
    _privacyTap.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _register() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(() =>
          _error = 'กรุณายอมรับเงื่อนไขการใช้บริการและนโยบายความเป็นส่วนตัว');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    // สร้าง Firebase Auth account
    final error = widget.completeProfile || _accountCreated
        ? null
        : await AuthService.register(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }

    _accountCreated = true;
    // Store business type independently from the selected subscription tier.
    try {
      await ShopService.createShop(
        name: _shopNameCtrl.text.trim(),
        email: AuthService.currentUser?.email ?? '',
        tier: _tier,
        shopType: _shopType,
        policyVersion: kPolicyVersion,
      );
      // Hardware is ordered separately after confirming equipment and terms.
      // Redeem referral code if the user entered one. Best-effort: a bad
      // code just doesn't credit anyone and never blocks signup.
      if (_referralCtrl.text.trim().isNotEmpty) {
        await ShopService.applyReferral(_referralCtrl.text);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'สร้างร้านไม่สำเร็จ: $e';
      });
      return;
    }

    // Auth state stream จะพา navigate ไป MainShell เองผ่าน StreamBuilder
    if (mounted) {
      setState(() => _loading = false);
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.completeProfile ? 'ตั้งค่าร้านของคุณ' : 'สมัครใช้งาน'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.completeProfile || _accountCreated || _shopStep
                            ? 'ขั้นตอน 2 จาก 2 · ตั้งค่าร้าน'
                            : 'ขั้นตอน 1 จาก 2 · บัญชีของคุณ',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    if (!widget.completeProfile &&
                        !_accountCreated &&
                        !_shopStep) ...[
                      SocialAuthButtons(
                          disabled: _loading,
                          onBusyChanged: (busy) {
                            if (mounted) setState(() => _loading = busy);
                          },
                          onSuccess: () =>
                              Navigator.of(context).popUntil((r) => r.isFirst)),
                      const SizedBox(height: 12),
                      if (!_emailChosen)
                        Center(
                            child: TextButton.icon(
                                onPressed: _loading
                                    ? null
                                    : () => setState(() => _emailChosen = true),
                                icon: const Icon(Icons.email_outlined),
                                label: const Text('สมัครด้วยอีเมล'))),
                      if (_emailChosen) ...[
                        const Divider(height: 32),
                        if (!widget.completeProfile &&
                            !_accountCreated &&
                            !_shopStep) ...[
                          Text('ข้อมูลบัญชี',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'อีเมล',
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'กรุณากรอกอีเมล'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'รหัสผ่าน',
                              hintText: 'อย่างน้อย 6 ตัวอักษร',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'กรุณากรอกรหัสผ่าน';
                              }
                              if (v.length < 6) {
                                return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPassCtrl,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _nextStep(),
                            decoration: const InputDecoration(
                              labelText: 'ยืนยันรหัสผ่าน',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v != _passCtrl.text) {
                                return 'รหัสผ่านไม่ตรงกัน';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                              onPressed: _loading ? null : _nextStep,
                              child: const Text('ถัดไป: ตั้งค่าร้าน')),
                        ],
                      ],
                    ],
                    if (widget.completeProfile ||
                        _accountCreated ||
                        _shopStep) ...[
                      if (!widget.completeProfile && !_accountCreated)
                        TextButton.icon(
                            onPressed: _loading
                                ? null
                                : () => setState(() => _shopStep = false),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('กลับไปแก้ไขบัญชี')),
                      if (widget.completeProfile || _accountCreated)
                        TextButton(
                            onPressed: _loading ? null : AuthService.signOut,
                            child: const Text(
                                'มีร้านเดิมแล้ว? กลับไปเข้าสู่ระบบ')),
                      // Trial banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.celebration_outlined,
                                color: Colors.green, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('ทดลองใช้ฟรี 60 วัน',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800)),
                                  Text('ไม่ต้องใส่ข้อมูลบัตรเครดิต',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade700)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      Text('ข้อมูลร้านค้า',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _shopNameCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อร้าน',
                          hintText: 'เช่น ร้านของชำสมหวัง',
                          prefixIcon: Icon(Icons.storefront_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'กรุณากรอกชื่อร้าน'
                            : null,
                      ),
                      const SizedBox(height: 24),

                      // Tier picker — 4-card ladder from Solo (BYOD, lowest CAC)
                      // up to Restaurant (full kit + kitchen). Default = Full
                      // because that's the mass-market sweet spot from the GTM
                      // plan. Trial is 60 days no matter what tier they pick;
                      // billing only kicks in if they stay past day 60.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('เลือกแผน',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface.withValues(alpha: 0.7))),
                          const SizedBox(width: 6),
                          Text('· ลองฟรี 60 วันก่อน เปลี่ยนภายหลังได้',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.5))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ShopType>(
                        segments: const [
                          ButtonSegment(
                              value: ShopType.retail,
                              label: Text('ร้านค้าปลีก'),
                              icon: Icon(Icons.storefront_outlined)),
                          ButtonSegment(
                              value: ShopType.restaurant,
                              label: Text('ร้านอาหาร'),
                              icon: Icon(Icons.restaurant_outlined)),
                        ],
                        selected: {_shopType},
                        onSelectionChanged: _loading
                            ? null
                            : (v) => setState(() => _shopType = v.first),
                      ),
                      const SizedBox(height: 12),
                      TierPicker(
                        shopType: _shopType,
                        selected: _tier,
                        onChanged: (t) => setState(() => _tier = t),
                      ),
                      const SizedBox(height: 24),
                      // Referral code — optional. Both the new shop and the
                      // referrer get +30 trial days (applied server-side).
                      TextFormField(
                        controller: _referralCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'รหัสแนะนำ (ไม่บังคับ)',
                          hintText: 'ได้รับฟรีเพิ่ม 30 วันทั้งคู่',
                          prefixIcon: Icon(Icons.card_giftcard_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 8),
                      // Terms + privacy acceptance — required before signup. Links
                      // open the hosted policy pages. Helps establish a lawful
                      // basis under Thailand's PDPA since shops store personal data
                      // (their own + their customers' loyalty/debt records).
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptedTerms,
                            onChanged: (v) =>
                                setState(() => _acceptedTerms = v ?? false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 13),
                              child: Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.5,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.75)),
                                  children: [
                                    const TextSpan(text: 'ฉันยอมรับ '),
                                    TextSpan(
                                      text: 'เงื่อนไขการใช้บริการ',
                                      style: TextStyle(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600),
                                      recognizer: _termsTap,
                                    ),
                                    const TextSpan(text: ' และ '),
                                    TextSpan(
                                      text: 'นโยบายความเป็นส่วนตัว',
                                      style: TextStyle(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w600),
                                      recognizer: _privacyTap,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: cs.onErrorContainer, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style:
                                        TextStyle(color: cs.onErrorContainer)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _loading ? null : _register,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('สมัครและเริ่มใช้งานฟรี'),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'หลัง 60 วัน เริ่มต้น ฿199/เดือน',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
