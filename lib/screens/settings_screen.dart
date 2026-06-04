import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../models/hardware_request.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/bank_notification_service.dart';
import '../services/entitlements.dart';
import '../services/hardware_service.dart';
import '../services/line_service.dart';
import '../services/settings_service.dart';
import '../services/shop_service.dart';
import '../widgets/upgrade_prompt.dart';
import 'subscription_screen.dart';
import '../main.dart' show themeNotifier;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _shopNameCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _lineUserIdCtrl = TextEditingController();
  final _promptpayIdCtrl = TextEditingController();
  final _promptpayNameCtrl = TextEditingController();
  final _serviceChargeCtrl = TextEditingController();
  bool _lineNotifyEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _savingLine = false;
  bool _savingPromptpay = false;
  bool _savingServiceCharge = false;
  bool _bankListenerGranted = false;
  ShopType _shopType = ShopType.retail;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _taxIdCtrl.dispose();
    _addressCtrl.dispose();
    _lineUserIdCtrl.dispose();
    _promptpayIdCtrl.dispose();
    _promptpayNameCtrl.dispose();
    _serviceChargeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await SettingsService.getSettings();
      final granted = await BankNotificationService.isPermissionGranted();
      final shop = await ShopService.getCurrentShop();
      if (mounted) {
        setState(() {
          _shopNameCtrl.text = (data['name'] as String?) ?? '';
          _taxIdCtrl.text = (data['taxId'] as String?) ?? '';
          _addressCtrl.text = (data['address'] as String?) ?? '';
          _lineUserIdCtrl.text = (data['lineUserId'] as String?) ?? '';
          _lineNotifyEnabled = (data['lineNotifyEnabled'] as bool?) ?? false;
          _promptpayIdCtrl.text = (data['promptpayId'] as String?) ?? '';
          _promptpayNameCtrl.text = (data['promptpayName'] as String?) ?? '';
          final sc = (data['serviceChargePercent'] ?? 0).toDouble();
          _serviceChargeCtrl.text = sc == 0 ? '' : sc.toStringAsFixed(0);
          _bankListenerGranted = granted;
          _shopType = shop?.shopType ?? ShopType.retail;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleBankListener() async {
    final granted = await BankNotificationService.requestPermission();
    if (!mounted) return;
    setState(() => _bankListenerGranted = granted);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted
            ? 'เปิดสิทธิ์อ่าน notification ธนาคารแล้ว — ออเดอร์จะ confirm อัตโนมัติ'
            : 'ยังไม่ได้รับสิทธิ์ — ลองอีกครั้งใน Settings → Notification access'),
        backgroundColor: granted ? Colors.green : null,
      ),
    );
  }

  Future<void> _saveServiceCharge() async {
    final raw = _serviceChargeCtrl.text.trim();
    final pct = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (pct == null || pct < 0 || pct > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ใส่ตัวเลข 0–100')),
      );
      return;
    }
    setState(() => _savingServiceCharge = true);
    try {
      await SettingsService.saveServiceChargePercent(pct);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(pct == 0
                ? 'ปิด service charge แล้ว'
                : 'ตั้ง service charge ${pct.toStringAsFixed(0)}% แล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingServiceCharge = false);
    }
  }

  Future<void> _savePromptPay() async {
    final id = _promptpayIdCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (id.isNotEmpty && id.length != 10 && id.length != 13 && id.length != 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PromptPay ID ต้องเป็นเบอร์ 10 หลัก, บัตรประชาชน 13 หลัก, หรือ e-wallet 15 หลัก',
          ),
        ),
      );
      return;
    }
    setState(() => _savingPromptpay = true);
    await SettingsService.savePromptPaySettings(
      promptpayId: id,
      promptpayName: _promptpayNameCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _savingPromptpay = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึก PromptPay แล้ว')),
      );
    }
  }

  Future<void> _saveLineSettings() async {
    setState(() => _savingLine = true);
    await SettingsService.saveLineSettings(
      lineUserId: _lineUserIdCtrl.text.trim(),
      enabled: _lineNotifyEnabled,
    );
    if (mounted) {
      setState(() => _savingLine = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการตั้งค่า LINE แล้ว')),
      );
    }
  }

  Future<void> _testLineNotify() async {
    if (_lineUserIdCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาใส่ LINE User ID ก่อน')),
      );
      return;
    }
    await _saveLineSettings();
    await LineService.sendMessage('✅ ทดสอบการแจ้งเตือน LINE จาก Pokpok POS สำเร็จ!');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งทดสอบแล้ว ตรวจสอบ LINE ของคุณ')),
      );
    }
  }

  Future<void> _save() async {
    final name = _shopNameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await SettingsService.saveSettings({
      'name': name,
      'taxId': _taxIdCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกการตั้งค่าแล้ว')),
      );
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (confirm == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = AuthService.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Shop info section
                _SectionTitle('ข้อมูลร้าน'),
                const SizedBox(height: 12),
                TextField(
                  controller: _shopNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อร้าน',
                    hintText: 'ร้านของชำ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _taxIdCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 13,
                  decoration: const InputDecoration(
                    labelText: 'เลขประจำตัวผู้เสียภาษี (ไม่บังคับ)',
                    hintText: '0000000000000',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ที่อยู่ร้าน',
                    hintText: 'เลขที่ ถนน ตำบล อำเภอ จังหวัด รหัสไปรษณีย์',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('บันทึกข้อมูลร้าน'),
                  ),
                ),

                const SizedBox(height: 28),
                const Divider(height: 1),
                const SizedBox(height: 20),

                // Plan — current tier + trial/billing status, with a tap
                // target that opens the full SubscriptionScreen for
                // upgrade/downgrade. Owner-facing source of truth for
                // "ฉันใช้แผนไหนอยู่?" and "ทดลองเหลือกี่วัน?"
                _SectionTitle('แผนปัจจุบัน'),
                const SizedBox(height: 8),
                StreamBuilder<Shop?>(
                  stream: ShopService.watchCurrentShop(),
                  builder: (context, snap) => Column(
                    children: [
                      _PlanTile(shop: snap.data),
                      if (snap.data != null) ...[
                        const SizedBox(height: 12),
                        _PlanCapabilities(tier: snap.data!.tier),
                        if (snap.data!.referralCode != null) ...[
                          const SizedBox(height: 12),
                          _ReferralCard(code: snap.data!.referralCode!),
                        ],
                      ],
                    ],
                  ),
                ),

                // Hardware tracker — only renders when there's an active
                // shipment (Lite/Full/Restaurant). Solo shops never see it.
                StreamBuilder<HardwareRequest?>(
                  stream: HardwareService.watchActive(),
                  builder: (context, snap) {
                    final req = snap.data;
                    if (req == null) return const SizedBox.shrink();
                    return Column(
                      children: [
                        const SizedBox(height: 24),
                        _SectionTitle('อุปกรณ์ของคุณ'),
                        const SizedBox(height: 8),
                        _HardwareTracker(request: req),
                      ],
                    );
                  },
                ),

                // Service charge — restaurant only. Auto-applied to every
                // table tab on close. Set to 0 to disable.
                if (_shopType == ShopType.restaurant) ...[
                  const SizedBox(height: 24),
                  _SectionTitle(
                    'Service charge',
                    helper: 'บวกเปอร์เซ็นต์บนยอดสินค้าตอนปิดบิล — 0 = ปิด',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _serviceChargeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'เปอร์เซ็นต์',
                            hintText: '10',
                            suffixText: '%',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed:
                            _savingServiceCharge ? null : _saveServiceCharge,
                        icon: _savingServiceCharge
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check, size: 18),
                        label: const Text('บันทึก'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Theme section
                Text('การแสดงผล',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, mode, _) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: Icon(mode == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode_outlined),
                    title: const Text('โหมดมืด'),
                    value: mode == ThemeMode.dark,
                    onChanged: (val) {
                      themeNotifier.value =
                          val ? ThemeMode.dark : ThemeMode.light;
                    },
                  ),
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // PromptPay payment section
                Text('รับเงินออนไลน์ (PromptPay)',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'ลูกค้าที่สั่งของออนไลน์จะเห็น QR PromptPay พร้อมจำนวนเงิน (มีเศษ\nสตางค์ระบุออเดอร์)\nเงินจะเข้าบัญชีร้านโดยตรง — Pokpok ไม่หักค่าธรรมเนียม',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptpayIdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PromptPay ID',
                    hintText: 'เบอร์โทร (เช่น 0812345678) หรือเลขบัตรประชาชน',
                    prefixIcon: Icon(Icons.qr_code_2),
                    border: OutlineInputBorder(),
                    helperText: '10 หลัก (เบอร์), 13 หลัก (บัตรประชาชน), หรือ 15 หลัก (e-wallet)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _promptpayNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อบัญชีผู้รับ',
                    hintText: 'นาย ก ข',
                    prefixIcon: Icon(Icons.account_balance_outlined),
                    border: OutlineInputBorder(),
                    helperText: 'แสดงในหน้าจ่ายเงินของลูกค้าเพื่อยืนยันความถูกต้อง',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _savingPromptpay ? null : _savePromptPay,
                    icon: _savingPromptpay
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('บันทึก PromptPay'),
                  ),
                ),

                if (Platform.isAndroid) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bankListenerGranted
                          ? Colors.green.withValues(alpha: 0.08)
                          : Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _bankListenerGranted
                            ? Colors.green.withValues(alpha: 0.5)
                            : Colors.amber.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _bankListenerGranted
                                  ? Icons.notifications_active
                                  : Icons.notifications_off_outlined,
                              size: 18,
                              color: _bankListenerGranted
                                  ? Colors.green.shade700
                                  : Colors.amber.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Auto-confirm จาก notification ธนาคาร',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _bankListenerGranted
                                    ? Colors.green.shade800
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'เมื่อเปิดสิทธิ์ แอปจะอ่าน notification "เงินเข้า" จากแอปธนาคาร '
                          '(K PLUS, SCB EASY, Krungthai NEXT, BBL, TTB, KMA) แล้ว '
                          'ยืนยันออเดอร์ที่ยอดตรงกันให้อัตโนมัติ\n\n'
                          '• อ่านเฉพาะแอปธนาคาร — ไม่ส่งเนื้อหา notification ออกจากเครื่อง\n'
                          '• ปิดเมื่อไหร่ก็ได้ที่ Settings → Notification access',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _toggleBankListener,
                            style: FilledButton.styleFrom(
                              backgroundColor: _bankListenerGranted
                                  ? Colors.green
                                  : Colors.amber.shade800,
                            ),
                            icon: Icon(
                              _bankListenerGranted
                                  ? Icons.check_circle
                                  : Icons.lock_open,
                            ),
                            label: Text(
                              _bankListenerGranted
                                  ? 'เปิดอยู่ — กดเพื่อจัดการ'
                                  : 'เปิดสิทธิ์ Notification access',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // LINE Notification section
                Text('การแจ้งเตือน LINE',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06C755).withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF06C755).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'วิธีเชื่อมต่อ LINE\n1. Add LINE OA ของร้าน\n2. ส่งข้อความใดก็ได้ → บอทตอบ User ID\n3. นำ ID มาใส่ด้านล่าง\nหรือส่ง "link:SHOP_ID" เพื่อเชื่อมอัตโนมัติ',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_active_outlined,
                      color: Color(0xFF06C755)),
                  title: const Text('เปิดแจ้งเตือนผ่าน LINE'),
                  value: _lineNotifyEnabled,
                  onChanged: (val) => setState(() => _lineNotifyEnabled = val),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lineUserIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'LINE User ID',
                    hintText: 'Uxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                    prefixIcon: Icon(Icons.chat_bubble_outline,
                        color: Color(0xFF06C755)),
                    border: OutlineInputBorder(),
                    helperText: 'รับได้จากการส่งข้อความหาบอท LINE',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _savingLine ? null : _saveLineSettings,
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF06C755)),
                        icon: _savingLine
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_outlined),
                        label: const Text('บันทึก'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _testLineNotify,
                      icon: const Icon(Icons.send_outlined,
                          color: Color(0xFF06C755)),
                      label: const Text('ทดสอบ',
                          style: TextStyle(color: Color(0xFF06C755))),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF06C755))),
                    ),
                  ],
                ),

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Subscription section
                Text('Subscription',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
                    ),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('จัดการ Subscription'),
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // Account section
                Text('บัญชีผู้ใช้',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.person, color: cs.onPrimaryContainer),
                  ),
                  title: Text(user?.email ?? ''),
                  subtitle: const Text('ผู้ดูแลระบบ'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _signOut,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('ออกจากระบบ',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Owner-facing summary of the current Pokpok plan — shows tier, billing
/// status (trial-days-left vs paid-days-left), and tappable to open the
/// full SubscriptionScreen for upgrade/downgrade. Tier label and price
/// are pulled from the Shop doc so they reflect any mid-session changes
/// (e.g. webhook flipping `subscriptionStatus` to active after payment).
class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.shop});
  final Shop? shop;

  static const _monthlyPriceByTier = {
    ShopTier.solo: 199,
    ShopTier.lite: 399,
    ShopTier.full: 599,
    ShopTier.restaurant: 1199,
  };

  static const _iconByTier = {
    ShopTier.solo: Icons.smartphone_outlined,
    ShopTier.lite: Icons.print_outlined,
    ShopTier.full: Icons.dashboard_outlined,
    ShopTier.restaurant: Icons.restaurant_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (shop == null) {
      return const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final s = shop!;
    final monthly = _monthlyPriceByTier[s.tier] ?? 599;
    final isRestaurant = s.tier == ShopTier.restaurant;
    final priceText = isRestaurant
        ? '฿$monthly/เดือน · ${s.locations} สาขา'
        : '฿$monthly/เดือน';

    final isTrial = s.subscriptionStatus == SubscriptionStatus.trial;
    final statusText = isTrial
        ? 'ทดลองใช้ฟรี — เหลือ ${s.trialDaysLeft} วัน'
        : (s.subscriptionStatus == SubscriptionStatus.active
            ? 'จ่ายแล้ว — เหลือ ${s.subscriptionDaysLeft} วัน'
            : 'หมดอายุแล้ว');
    final statusColor = isTrial
        ? Colors.orange.shade700
        : (s.subscriptionStatus == SubscriptionStatus.active
            ? Colors.green.shade700
            : Colors.red);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      ),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(_iconByTier[s.tier] ?? Icons.dashboard_outlined,
                color: cs.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(s.tier.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text(priceText,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurface.withValues(alpha: 0.65))),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(statusText,
                      style: TextStyle(
                          fontSize: 12,
                          color: statusColor,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// Read-only delivery tracker for the shop's active hardware kit. Mirrors
/// the status the founder/sales agent advances from their admin tool —
/// gives the owner a "where's my printer?" answer without a support
/// message. Shows a 4-step progress bar + deposit/up-front summary.
class _HardwareTracker extends StatelessWidget {
  const _HardwareTracker({required this.request});
  final HardwareRequest request;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final delivered = request.status == HardwareStatus.delivered;
    final returned = request.status == HardwareStatus.returned;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                delivered
                    ? Icons.check_circle
                    : (returned
                        ? Icons.keyboard_return
                        : Icons.local_shipping_outlined),
                color: delivered ? Colors.green.shade600 : cs.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(request.status.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(request.kit.label,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.65))),
          if (!returned) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: request.status.progress,
                minHeight: 6,
                backgroundColor: cs.outlineVariant,
                color: delivered ? Colors.green.shade600 : cs.primary,
              ),
            ),
          ],
          if (request.deposit > 0 || request.upfront > 0) ...[
            const SizedBox(height: 10),
            if (request.deposit > 0)
              _kv(context, 'มัดจำ (คืนได้)',
                  '฿${request.deposit.toStringAsFixed(0)}'),
            if (request.upfront > 0)
              _kv(context, 'ค่าอุปกรณ์',
                  '฿${request.upfront.toStringAsFixed(0)}'),
          ],
          if (request.note != null && request.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(request.note!,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6))),
          Text(v,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Share-your-code card. Surfaces the shop's referral code with a copy
/// button + the "ทั้งคู่ได้ฟรี 30 วัน" hook. The reward is applied
/// server-side by the applyReferral function when the friend enters this
/// code at signup.
class _ReferralCard extends StatelessWidget {
  const _ReferralCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.card_giftcard_outlined,
                  size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('แนะนำเพื่อน — ได้ฟรี 30 วันทั้งคู่',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('ให้เพื่อนกรอกรหัสนี้ตอนสมัคร แล้วทั้งคุณและเพื่อนได้ทดลองเพิ่มคนละ 30 วัน',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.65))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกรหัสแล้ว')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('คัดลอก'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-tier capability checklist. Renders every feature the platform
/// offers, with a check for the ones included in the owner's tier and a
/// lock for the ones that need an upgrade. Tapping a lock opens the
/// upgrade prompt scoped to that specific feature.
///
/// Goal: turn the "what am I missing?" question into a one-screen answer
/// the owner can scan in 5 seconds — and convert that curiosity into a
/// concrete upgrade ask via the tap target.
class _PlanCapabilities extends StatelessWidget {
  const _PlanCapabilities({required this.tier});
  final ShopTier tier;

  static const _features = [
    EntitlementFeature.paperReceipt,
    EntitlementFeature.inventory,
    EntitlementFeature.customerDb,
    EntitlementFeature.loyalty,
    EntitlementFeature.advancedReports,
    EntitlementFeature.tables,
    EntitlementFeature.kitchen,
    EntitlementFeature.multiBranch,
    EntitlementFeature.apiSync,
  ];

  bool _has(EntitlementFeature f) => switch (f) {
        EntitlementFeature.paperReceipt =>
          Entitlements.canUsePaperReceipt(tier),
        EntitlementFeature.inventory => Entitlements.canUseInventory(tier),
        EntitlementFeature.customerDb =>
          Entitlements.canUseCustomerDb(tier),
        EntitlementFeature.loyalty => Entitlements.canUseLoyalty(tier),
        EntitlementFeature.advancedReports =>
          Entitlements.canUseAdvancedReports(tier),
        EntitlementFeature.kitchen => Entitlements.canUseKitchen(tier),
        EntitlementFeature.tables => Entitlements.canUseTables(tier),
        EntitlementFeature.multiBranch =>
          Entitlements.canUseMultiBranch(tier),
        EntitlementFeature.apiSync => Entitlements.canUseApiSync(tier),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('สิ่งที่มีในแผน',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.onSurface.withValues(alpha: 0.55))),
          const SizedBox(height: 6),
          for (final f in _features)
            _CapabilityRow(
              feature: f,
              included: _has(f),
            ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.feature, required this.included});
  final EntitlementFeature feature;
  final bool included;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: included
          ? null
          : () => showUpgradePrompt(context, feature: feature),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              included ? Icons.check_circle : Icons.lock_outline,
              size: 16,
              color: included
                  ? Colors.green.shade600
                  : cs.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                feature.label,
                style: TextStyle(
                  fontSize: 13,
                  color: included
                      ? cs.onSurface
                      : cs.onSurface.withValues(alpha: 0.5),
                  decoration:
                      included ? null : TextDecoration.lineThrough,
                  decorationColor: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
            if (!included)
              Text('อัพเกรด',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary)),
          ],
        ),
      ),
    );
  }
}

/// Small section heading + optional helper line. Replaces the repeated
/// `Text(... titleSmall + primary color)` blocks across this screen so all
/// section labels look identical and the helper text styling stays in one
/// place.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.helper});
  final String title;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.primary,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}
