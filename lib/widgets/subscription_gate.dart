import 'package:flutter/material.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/shop_service.dart';
import '../screens/subscription_screen.dart';

class SubscriptionGate extends StatelessWidget {
  final Widget child;
  const SubscriptionGate({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Shop?>(
      stream: ShopService.watchCurrentShop(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || snap.data == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final shop = snap.data!;
        final shopId = AuthService.shopId;
        if (shopId != null) NotificationService.initFCM(shopId);

        // subscription หมดอายุ → ไปหน้า subscription
        if (!shop.isAccessAllowed) {
          return const SubscriptionScreen();
        }

        // trial ยังใช้งานได้ → แสดง banner เตือน
        if (shop.subscriptionStatus == SubscriptionStatus.trial) {
          return _TrialBanner(daysLeft: shop.trialDaysLeft, child: child);
        }

        return child;
      },
    );
  }
}

class _TrialBanner extends StatelessWidget {
  final int daysLeft;
  final Widget child;
  const _TrialBanner({required this.daysLeft, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: daysLeft <= 3 ? Colors.red : Colors.orange,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen()),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              // Single-line layout — Android Thai font rendered wider than
              // iOS and used to wrap mid-sentence, breaking digit groups
              // off-pattern. Ellipsis + Row keeps the banner one line on
              // every device.
              child: Row(
                children: [
                  const Icon(Icons.celebration_outlined,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      daysLeft > 0
                          ? 'ทดลองใช้ฟรี · เหลือ $daysLeft วัน'
                          : 'วันสุดท้ายของการทดลองใช้',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'สมัครต่อ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
