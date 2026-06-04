import 'package:flutter/material.dart';

import '../models/shop.dart';

/// Compact 4-tier picker — used on register screen and as a sub-widget
/// in the subscription/upgrade screen. Renders one row per tier with
/// price + 1-line description; tap to select. Tier 3 (Full) gets a
/// "แนะนำ" badge as the mass-market default.
class TierPicker extends StatelessWidget {
  const TierPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final ShopTier selected;
  final void Function(ShopTier) onChanged;

  static const _meta = <ShopTier, _TierMeta>{
    ShopTier.solo: _TierMeta(
      icon: Icons.smartphone_outlined,
      monthlyPrice: 199,
      tagline: 'BYOD · ลองก่อนค่อยลงทุน hardware',
    ),
    ShopTier.lite: _TierMeta(
      icon: Icons.print_outlined,
      monthlyPrice: 399,
      tagline: 'มี tablet แล้ว ต้องการพิมพ์ใบเสร็จ + drawer',
    ),
    ShopTier.full: _TierMeta(
      icon: Icons.dashboard_outlined,
      monthlyPrice: 599,
      tagline: 'ครบชุด hardware + 3 users + onsite repair',
      recommended: true,
    ),
    ShopTier.restaurant: _TierMeta(
      icon: Icons.restaurant_outlined,
      monthlyPrice: 1199,
      tagline: 'ครัว + โต๊ะ + multi-branch · ต่อสาขา',
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final tier in ShopTier.values) ...[
          _TierRow(
            tier: tier,
            meta: _meta[tier]!,
            selected: selected == tier,
            onTap: () => onChanged(tier),
          ),
          if (tier != ShopTier.values.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TierMeta {
  const _TierMeta({
    required this.icon,
    required this.monthlyPrice,
    required this.tagline,
    this.recommended = false,
  });

  final IconData icon;
  final int monthlyPrice;
  final String tagline;
  final bool recommended;
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final ShopTier tier;
  final _TierMeta meta;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.08) : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              meta.icon,
              size: 26,
              color:
                  selected ? cs.primary : cs.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tier.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: selected ? cs.primary : cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (meta.recommended) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: cs.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'แนะนำ',
                            style: TextStyle(
                              fontSize: 9,
                              color: cs.onPrimary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        '฿${meta.monthlyPrice}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: selected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      Text(
                        tier == ShopTier.restaurant ? '/เดือน·สาขา' : '/เดือน',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.tagline,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
