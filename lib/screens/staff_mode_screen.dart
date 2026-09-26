import 'package:flutter/material.dart';
import '../services/staff_access_service.dart';
import '../utils/operation_error.dart';
import 'pos_screen.dart';
import 'user_switch_screen.dart';

class StaffModeScreen extends StatelessWidget {
  const StaffModeScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: StaffAccessService.unlocked,
        builder: (context, unlocked, _) {
          if (!unlocked) return const UserSwitchScreen();
          return Scaffold(
              body: SafeArea(
                  child: Column(children: [
            Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: FutureBuilder<Map<String, dynamic>>(
                      future: StaffAccessService.workspace(),
                      builder: (context, snap) => Text(snap.hasError
                          ? operationError(snap.error!)
                          : 'พนักงาน: ${snap.data?['staffName'] ?? 'กำลังตรวจสิทธิ์…'}')),
                  subtitle: const Text(
                      'สิทธิ์ขายและรับเงิน · งานโต๊ะ/ครัวให้เจ้าของร้านจัดการ'),
                  trailing: TextButton.icon(
                      onPressed: () =>
                          StaffAccessService.unlocked.value = false,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('ล็อก / เปลี่ยนผู้ใช้')),
                )),
            const Expanded(child: PosScreen()),
          ])));
        },
      );
}
