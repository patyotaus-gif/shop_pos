import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/shop_service.dart';
import '../widgets/app_version_text.dart';

/// Subscription status + renewal screen. Used both as the gated screen when
/// a trial/subscription lapses and as the "แผนการใช้งาน" destination from
/// Settings.
///
/// Plan selection + payment intentionally live on the web
/// (pok-pok.app/subscribe), not in the app: showing prices and a buy button
/// inside the iOS app would run into Apple's in-app-purchase rules, so the
/// app just links out. The web checkout reuses the same Stripe flow.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ออกจากระบบ?'),
        content: const Text('คุณจะต้องเข้าสู่ระบบใหม่อีกครั้ง'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ออกจากระบบ')),
        ],
      ),
    );
    if (ok == true) await AuthService.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Shop?>(
      stream: ShopService.watchCurrentShop(),
      builder: (context, snap) {
        final shop = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('แผนการใช้งาน'),
            centerTitle: true,
            // The gate shows this screen when access lapses; without this
            // there's no way out of a logged-in-but-expired account.
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                tooltip: 'ออกจากระบบ',
                onPressed: () => _confirmSignOut(context),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _StatusBanner(shop: shop),
                const SizedBox(height: 20),
                const _RenewOnWebCard(),
                const SizedBox(height: 16),
                _MarketplaceFootnote(),
                const SizedBox(height: 20),
                const AppVersionText(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.shop});
  final Shop? shop;

  @override
  Widget build(BuildContext context) {
    if (shop == null) return const SizedBox.shrink();

    final isExpiredTrial =
        shop!.subscriptionStatus == SubscriptionStatus.trial &&
            !(shop!.trialEndsAt?.isAfter(DateTime.now()) ?? false);
    final isExpiredSub =
        shop!.subscriptionStatus == SubscriptionStatus.active &&
            !(shop!.subscriptionEndsAt?.isAfter(DateTime.now()) ?? false);

    String message;
    Color color;
    IconData icon;

    if (isExpiredTrial) {
      message = 'หมดระยะทดลองใช้แล้ว ต่ออายุเพื่อใช้งานต่อ';
      color = Colors.red;
      icon = Icons.timer_off_outlined;
    } else if (isExpiredSub) {
      message = 'subscription หมดอายุ — ต่ออายุเพื่อใช้งานต่อ';
      color = Colors.red;
      icon = Icons.credit_card_off_outlined;
    } else if (shop!.subscriptionStatus == SubscriptionStatus.trial) {
      message =
          'ทดลองใช้ฟรี — เหลือ ${shop!.trialDaysLeft} วัน · แผนปัจจุบัน ${shop!.tier.label}';
      color = Colors.orange;
      icon = Icons.hourglass_bottom_outlined;
    } else if (shop!.subscriptionStatus == SubscriptionStatus.active) {
      message =
          'ใช้งาน ${shop!.tier.label} · เหลือ ${shop!.subscriptionDaysLeft} วัน';
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else {
      message = 'subscription หมดอายุ';
      color = Colors.red;
      icon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// CTA that sends the owner to the web checkout to pick a plan and pay.
class _RenewOnWebCard extends StatelessWidget {
  const _RenewOnWebCard();

  static const _url = 'https://pok-pok.app/subscribe';

  Future<void> _open() async {
    final uri = Uri.parse(_url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: cs.primary, size: 24),
              const SizedBox(width: 10),
              const Text('ต่ออายุ & เลือกแผน',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'ดูแผนทั้งหมด เปรียบเทียบราคา และชำระเงินได้ที่เว็บของเรา — '
            'ปลอดภัยผ่าน Stripe (บัตร · PromptPay · TrueMoney) '
            'เติมเวลาใช้งานทันทีหลังชำระ',
            style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: cs.onSurface.withValues(alpha: 0.75)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('เปิดหน้าต่ออายุ (pok-pok.app)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'เข้าสู่ระบบด้วยบัญชีร้านเดียวกับในแอป',
              style: TextStyle(
                  fontSize: 11.5,
                  color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarketplaceFootnote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined,
              size: 18, color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Marketplace ใช้ได้ในทุกแผน · คิด take rate 2.5% เฉพาะตอนสั่งของจาก supplier',
              style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.65)),
            ),
          ),
        ],
      ),
    );
  }
}
