import 'package:flutter/material.dart';

import '../models/shop.dart';
import '../screens/subscription_screen.dart';
import '../services/entitlements.dart';

/// Bottom sheet shown when the user taps a feature their tier doesn't
/// include. Tells them which tier unlocks it and routes to the
/// SubscriptionScreen with one tap. Keeps the upgrade ask warm and
/// in-context instead of a generic "upgrade now" splash.
Future<void> showUpgradePrompt(
  BuildContext context, {
  required EntitlementFeature feature,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _UpgradePromptSheet(feature: feature),
  );
}

class _UpgradePromptSheet extends StatelessWidget {
  const _UpgradePromptSheet({required this.feature});
  final EntitlementFeature feature;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final minTier = Entitlements.minTierFor(feature);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Icon(Icons.lock_outline, color: cs.primary, size: 36),
            const SizedBox(height: 12),
            Text(
              feature.label,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'ฟีเจอร์นี้อยู่ในแผน ${minTier.label} ขึ้นไป',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SubscriptionScreen()),
                );
              },
              icon: const Icon(Icons.arrow_upward, size: 18),
              label: Text('อัพเกรดเป็น ${minTier.label}'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยังก่อน'),
            ),
          ],
        ),
      ),
    );
  }
}
