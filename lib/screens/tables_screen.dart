import 'package:flutter/material.dart';

/// Restaurant mode tab — table management (planned for PR 2).
/// Renders a "coming soon" state for now so the nav entry is wired up
/// and shop owners who picked the restaurant type see where it will live.
class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('โต๊ะ'), centerTitle: true),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.table_restaurant_outlined,
                  size: 72, color: cs.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text('จัดการโต๊ะ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'กำลังพัฒนา — เปิดใช้งานเร็วๆ นี้\nจะรองรับ: ผังโต๊ะ, เปิด/ปิดบิล, แยกบิล',
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
