import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/shop.dart';
import '../services/shop_service.dart';
import '../services/stripe_service.dart';

/// Subscription / upgrade screen — used both as the gated screen when a
/// trial expires and as the in-app "เปลี่ยนแผน" destination from Settings.
/// Shows all four tiers with a monthly/yearly toggle and per-location
/// stepper for the Restaurant tier.
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String _billingCycle = 'monthly';

  // Restaurant tier is priced per location — owners can bump this on the
  // Restaurant card itself before subscribing. Other tiers ignore it.
  int _restaurantLocations = 1;

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
            // Hide back arrow when this is the gated screen (no parent
            // route to pop back to) — Flutter handles that automatically.
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _StatusBanner(shop: shop),
                const SizedBox(height: 20),
                _BillingCycleToggle(
                  value: _billingCycle,
                  onChanged: (v) => setState(() => _billingCycle = v),
                ),
                const SizedBox(height: 16),
                for (final tier in ShopTier.values) ...[
                  _TierCard(
                    tier: tier,
                    cycle: _billingCycle,
                    currentTier: shop?.tier,
                    locations: tier == ShopTier.restaurant
                        ? _restaurantLocations
                        : 1,
                    onLocationsChanged: tier == ShopTier.restaurant
                        ? (n) => setState(() => _restaurantLocations = n)
                        : null,
                  ),
                  if (tier != ShopTier.values.last)
                    const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                _MarketplaceFootnote(),
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
      message = 'หมดระยะทดลองใช้แล้ว เลือกแผนเพื่อใช้งานต่อ';
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
                style:
                    TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _BillingCycleToggle extends StatelessWidget {
  const _BillingCycleToggle({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final void Function(String) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String key, String label, {String? badge}) {
      final selected = value == key;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(key),
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.onPrimary.withValues(alpha: 0.18)
                          : Colors.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: selected ? cs.onPrimary : Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          seg('monthly', 'รายเดือน'),
          seg('yearly', 'รายปี', badge: 'ประหยัด 2 เดือน'),
        ],
      ),
    );
  }
}

/// Tier price book — both cycles, with a couple of feature lines for the
/// pricing card. Yearly = 10 × monthly (~2 months free) across the board.
class _TierPricing {
  const _TierPricing({
    required this.monthly,
    required this.yearly,
    required this.features,
    this.perLocation = false,
    this.recommended = false,
    this.hardwareNote,
  });

  final int monthly;
  final int yearly; // baht / year (or per location-year for restaurant)
  final List<String> features;
  final bool perLocation;
  final bool recommended;
  final String? hardwareNote;
}

const _pricing = <ShopTier, _TierPricing>{
  ShopTier.solo: _TierPricing(
    monthly: 199,
    yearly: 1990,
    hardwareNote: 'BYOD — ลูกค้าใช้มือถือ/tablet ของตัวเอง',
    features: [
      'POS ขาย, รับเงิน, ใบเสร็จ digital',
      'Daily report พื้นฐาน',
      'QR PromptPay built-in',
      'Marketplace ordering (ใช้ได้)',
      '1 user, 1 location',
    ],
  ),
  ShopTier.lite: _TierPricing(
    monthly: 399,
    yearly: 3990,
    hardwareNote: 'Tablet ของลูกค้า + Pokpok kit · ฿4,000 upfront หรือผ่อน 24 เดือน',
    features: [
      'ทุกอย่างใน Solo',
      'ใบเสร็จกระดาษ + cash drawer',
      'Inventory tracking พื้นฐาน',
      'Customer database',
      'Support 48hr SLA',
    ],
  ),
  ShopTier.full: _TierPricing(
    monthly: 599,
    yearly: 5990,
    recommended: true,
    hardwareNote: 'ครบชุด: tablet 10" + printer + drawer + stand · ฿1,000 deposit คืนได้',
    features: [
      'ทุกอย่างใน Lite',
      'Hardware bundle (ไม่ต้องลงทุน upfront)',
      '3 users (เจ้าของ + พนักงาน)',
      'Customer loyalty พื้นฐาน',
      'Advanced reports + onsite repair 24hr SLA',
    ],
  ),
  ShopTier.restaurant: _TierPricing(
    monthly: 1199,
    yearly: 11990,
    perLocation: true,
    hardwareNote: 'Full kit + kitchen printer + order pad ที่ 2 · ฿2,000 deposit/สาขา',
    features: [
      'ทุกอย่างใน Full',
      'Kitchen printer + order pad',
      'Table management + ผังโต๊ะ',
      'Multi-branch dashboard',
      'Users + roles ไม่จำกัด · API + Xero/FlowAccount sync',
    ],
  ),
};

class _TierCard extends StatefulWidget {
  const _TierCard({
    required this.tier,
    required this.cycle,
    required this.currentTier,
    required this.locations,
    this.onLocationsChanged,
  });

  final ShopTier tier;
  final String cycle;
  final ShopTier? currentTier;
  final int locations;
  final void Function(int)? onLocationsChanged;

  @override
  State<_TierCard> createState() => _TierCardState();
}

class _TierCardState extends State<_TierCard> {
  bool _loading = false;

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    try {
      final url = await StripeService.createCheckoutUrl(
        tier: widget.tier,
        billingCycle: widget.cycle,
        locations: widget.tier == ShopTier.restaurant ? widget.locations : 1,
      );
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _pricing[widget.tier]!;
    final isCurrent = widget.currentTier == widget.tier;
    final isYearly = widget.cycle == 'yearly';
    final price = isYearly ? p.yearly : p.monthly;
    final displayPrice = widget.tier == ShopTier.restaurant
        ? price * widget.locations
        : price;

    final cycleLabel = isYearly
        ? (p.perLocation ? '/ปี · ${widget.locations} สาขา' : '/ปี')
        : (p.perLocation ? '/เดือน · ${widget.locations} สาขา' : '/เดือน');

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.recommended
                ? cs.primary.withValues(alpha: 0.05)
                : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent
                  ? Colors.green
                  : (p.recommended ? cs.primary : cs.outlineVariant),
              width: isCurrent || p.recommended ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.tier.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        const SizedBox(height: 2),
                        if (p.hardwareNote != null)
                          Text(
                            p.hardwareNote!,
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    cs.onSurface.withValues(alpha: 0.6)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('฿${_money(displayPrice)}',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: cs.primary)),
                      Text(cycleLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  cs.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ],
              ),
              if (widget.tier == ShopTier.restaurant) ...[
                const SizedBox(height: 10),
                _LocationsStepper(
                  value: widget.locations,
                  onChanged: widget.onLocationsChanged ?? (_) {},
                ),
              ],
              const SizedBox(height: 12),
              for (final f in p.features)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading || isCurrent ? null : _subscribe,
                  style: p.recommended
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: cs.secondary),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(isCurrent
                          ? 'แผนปัจจุบัน'
                          : 'เลือก ${widget.tier.label}'),
                ),
              ),
            ],
          ),
        ),
        if (p.recommended)
          Positioned(
            top: -10,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                'แนะนำ',
                style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5),
              ),
            ),
          ),
        if (isCurrent)
          Positioned(
            top: -10,
            left: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Text(
                'แผนปัจจุบัน',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  static String _money(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _LocationsStepper extends StatelessWidget {
  const _LocationsStepper({required this.value, required this.onChanged});
  final int value;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text('จำนวนสาขา',
            style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.7))),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed:
              value > 1 ? () => onChanged((value - 1).clamp(1, 99)) : null,
        ),
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged((value + 1).clamp(1, 99)),
        ),
      ],
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
