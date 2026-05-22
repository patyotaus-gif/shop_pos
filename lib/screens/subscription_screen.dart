import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/shop.dart';
import '../services/shop_service.dart';
import '../services/stripe_service.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Shop?>(
      stream: ShopService.watchCurrentShop(),
      builder: (context, snap) {
        final shop = snap.data;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(),
                  _StatusBanner(shop: shop),
                  const SizedBox(height: 32),
                  Text(
                    'เลือกแผนการใช้งาน',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  _PlanCard(
                    plan: 'monthly',
                    title: 'รายเดือน',
                    price: '฿299',
                    period: '/เดือน',
                    features: const [
                      'ใช้งานได้ 1 เดือน',
                      'สินค้าไม่จำกัด',
                      'รายงานการขาย',
                      'ส่งออก PDF',
                    ],
                    isBestValue: false,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    plan: 'yearly',
                    title: 'รายปี',
                    price: '฿2,990',
                    period: '/ปี',
                    subtitle: 'ประหยัด ฿598 (เทียบเท่า ฿249/เดือน)',
                    features: const [
                      'ใช้งานได้ 1 ปี',
                      'สินค้าไม่จำกัด',
                      'รายงานการขาย',
                      'ส่งออก PDF',
                    ],
                    isBestValue: true,
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final Shop? shop;
  const _StatusBanner({required this.shop});

  @override
  Widget build(BuildContext context) {
    if (shop == null) return const SizedBox.shrink();

    final isExpiredTrial = shop!.subscriptionStatus == SubscriptionStatus.trial &&
        !(shop!.trialEndsAt?.isAfter(DateTime.now()) ?? false);
    final isExpiredSub = shop!.subscriptionStatus == SubscriptionStatus.active &&
        !(shop!.subscriptionEndsAt?.isAfter(DateTime.now()) ?? false);

    String message;
    Color color;
    IconData icon;

    if (isExpiredTrial) {
      message = 'หมดระยะทดลองใช้แล้ว กรุณาเลือกแผนเพื่อใช้งานต่อ';
      color = Colors.red;
      icon = Icons.timer_off_outlined;
    } else if (isExpiredSub) {
      message = 'subscription หมดอายุแล้ว กรุณาต่ออายุเพื่อใช้งานต่อ';
      color = Colors.red;
      icon = Icons.credit_card_off_outlined;
    } else if (shop!.subscriptionStatus == SubscriptionStatus.trial) {
      message = 'เหลือเวลาทดลองใช้อีก ${shop!.trialDaysLeft} วัน';
      color = Colors.orange;
      icon = Icons.hourglass_bottom_outlined;
    } else if (shop!.subscriptionStatus == SubscriptionStatus.active) {
      message = 'subscription ใช้งานได้ถึง ${shop!.subscriptionDaysLeft} วัน';
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else {
      message = 'subscription หมดอายุ';
      color = Colors.red;
      icon = Icons.error_outline;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatefulWidget {
  final String plan;
  final String title;
  final String price;
  final String period;
  final String? subtitle;
  final List<String> features;
  final bool isBestValue;

  const _PlanCard({
    required this.plan,
    required this.title,
    required this.price,
    required this.period,
    required this.features,
    required this.isBestValue,
    this.subtitle,
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _loading = false;

  Future<void> _subscribe() async {
    setState(() => _loading = true);
    try {
      final url = await StripeService.createCheckoutUrl(widget.plan);
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isBestValue
                ? cs.primaryContainer.withValues(alpha: 0.5)
                : cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isBestValue ? cs.primary : cs.outline,
              width: widget.isBestValue ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.price,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: cs.primary),
                        ),
                        TextSpan(
                          text: widget.period,
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(widget.subtitle!,
                    style: TextStyle(
                        fontSize: 12, color: Colors.green.shade700)),
              ],
              const SizedBox(height: 12),
              ...widget.features.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Text(f, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _subscribe,
                  style: widget.isBestValue
                      ? null
                      : FilledButton.styleFrom(
                          backgroundColor: cs.secondary),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text('เลือกแผน${widget.title}'),
                ),
              ),
            ],
          ),
        ),
        if (widget.isBestValue)
          Positioned(
            top: -12,
            right: 16,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'คุ้มที่สุด',
                style: TextStyle(
                    color: cs.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}
