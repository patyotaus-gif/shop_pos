import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/line_service.dart';
import '../services/settings_service.dart';
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
  bool _lineNotifyEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _savingLine = false;
  bool _savingPromptpay = false;

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
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final data = await SettingsService.getSettings();
      if (mounted) {
        setState(() {
          _shopNameCtrl.text = (data['name'] as String?) ?? '';
          _taxIdCtrl.text = (data['taxId'] as String?) ?? '';
          _addressCtrl.text = (data['address'] as String?) ?? '';
          _lineUserIdCtrl.text = (data['lineUserId'] as String?) ?? '';
          _lineNotifyEnabled = (data['lineNotifyEnabled'] as bool?) ?? false;
          _promptpayIdCtrl.text = (data['promptpayId'] as String?) ?? '';
          _promptpayNameCtrl.text = (data['promptpayName'] as String?) ?? '';
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
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
                Text('ข้อมูลร้าน',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: cs.primary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _shopNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อร้าน',
                    hintText: 'ร้านของชำ',
                    prefixIcon: Icon(Icons.storefront_outlined),
                    border: OutlineInputBorder(),
                    helperText: 'ชื่อนี้จะแสดงบนใบเสร็จและรายงาน',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _taxIdCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 13,
                  decoration: const InputDecoration(
                    labelText: 'เลขประจำตัวผู้เสียภาษี',
                    hintText: '0000000000000',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                    helperText: '13 หลัก (ไม่บังคับ)',
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
                    prefixIcon: Icon(Icons.location_on_outlined),
                    border: OutlineInputBorder(),
                    helperText: 'แสดงในรายงานสำหรับยื่นภาษี',
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('บันทึก'),
                  ),
                ),

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
