import 'package:flutter/material.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/shop_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  ShopType _shopType = ShopType.retail;
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // สร้าง Firebase Auth account
    final error = await AuthService.register(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );

    if (error != null) {
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }

    // สร้าง shop document ใน Firestore
    //
    // Tier เลือกอัตโนมัติจาก shopType ที่ผู้ใช้กดบนหน้า register:
    //   - ร้านอาหาร → Tier 4 (Restaurant) — ครบ kitchen + tables + branches
    //   - ขายปลีก    → Tier 3 (Full) — mass-market default, hardware bundle
    // Tier picker UI เต็มรูปแบบ (เลือก Solo/Lite/Full) มาใน Phase B
    try {
      await ShopService.createShop(
        name: _shopNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        tier: _shopType == ShopType.restaurant
            ? ShopTier.restaurant
            : ShopTier.full,
        shopType: _shopType,
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'สร้างร้านไม่สำเร็จ: $e';
      });
      return;
    }

    // Auth state stream จะพา navigate ไป MainShell เองผ่าน StreamBuilder
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('สมัครใช้งาน'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.bold)),
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อร้าน' : null,
                ),
                const SizedBox(height: 16),

                // ประเภทร้าน — ตัดสิน workflow ของ POS (retail = ขายปลีก
                // ทั่วไป, restaurant = มีโต๊ะ + ครัว + modifier). เลือกตอน
                // สมัครครั้งเดียว ปกติไม่เปลี่ยน
                Text('ประเภทร้าน',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.7))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ShopTypeCard(
                        icon: Icons.store_outlined,
                        label: 'ขายปลีก',
                        subtitle: 'ของชำ มินิมาร์ท ขายของทั่วไป',
                        selected: _shopType == ShopType.retail,
                        onTap: () =>
                            setState(() => _shopType = ShopType.retail),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ShopTypeCard(
                        icon: Icons.restaurant_outlined,
                        label: 'ร้านอาหาร',
                        subtitle: 'มีโต๊ะ ครัว เครื่องดื่ม คาเฟ่',
                        selected: _shopType == ShopType.restaurant,
                        onTap: () =>
                            setState(() => _shopType = ShopType.restaurant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('ข้อมูลบัญชี',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.primary, fontWeight: FontWeight.bold)),
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'กรุณากรอกอีเมล' : null,
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
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่าน';
                    if (v.length < 6) return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _register(),
                  decoration: const InputDecoration(
                    labelText: 'ยืนยันรหัสผ่าน',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v != _passCtrl.text) return 'รหัสผ่านไม่ตรงกัน';
                    return null;
                  },
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
                              style: TextStyle(color: cs.onErrorContainer)),
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
                    'หลังทดลองใช้ ราคาเริ่มต้น ฿299/เดือน',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShopTypeCard extends StatelessWidget {
  const _ShopTypeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 28,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.7)),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.primary : cs.onSurface)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}
