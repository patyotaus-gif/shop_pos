import 'package:flutter/material.dart';

/// Restaurant mode tab — kitchen ticket display (planned for PR 4).
/// Placeholder so the nav entry exists in the restaurant build today.
class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ครัว'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.soup_kitchen_outlined,
                  size: 72, color: cs.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text('Kitchen Display',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'กำลังพัฒนา — เปิดใช้งานเร็วๆ นี้\nจะรองรับ: รายการสั่ง, สถานะ cooking/ready, print ใบสั่งครัว',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
