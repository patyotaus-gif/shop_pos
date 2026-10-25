import 'package:flutter/material.dart';
import '../services/staff_access_service.dart';
import '../models/staff_member.dart';
import '../utils/operation_error.dart';
import 'pos_screen.dart';
import 'user_switch_screen.dart';
import 'tables_screen.dart';
import 'orders_screen.dart';
import 'kitchen_screen.dart';
import 'staff_tools_screen.dart';

class StaffModeScreen extends StatelessWidget {
  const StaffModeScreen({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: StaffAccessService.unlocked,
        builder: (context, unlocked, _) {
          if (!unlocked) return const UserSwitchScreen();
          return DefaultTabController(
              length: 5,
              child: Scaffold(
                  body: SafeArea(
                      child: Column(children: [
                Material(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: FutureBuilder<Map<String, dynamic>>(
                          future: StaffAccessService.workspace(),
                          builder: (context, snap) => Text(
                              snap.hasError
                                  ? operationError(snap.error!)
                                  : '${snap.data?['staffName'] ?? 'กำลังตรวจสิทธิ์…'} · ${StaffRole.values.firstWhere((r) => r.name == snap.data?['position'], orElse: () => StaffRole.cashier).label}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                      subtitle: const Text('ขาย รับเงิน โต๊ะ ออเดอร์ และครัว'),
                      trailing: TextButton.icon(
                          onPressed: () =>
                              StaffAccessService.unlocked.value = false,
                          icon: const Icon(Icons.lock_outline),
                          label: const Text('ล็อก / เปลี่ยนผู้ใช้')),
                    )),
                const TabBar(isScrollable: true, tabs: [
                  Tab(text: 'ขาย'),
                  Tab(text: 'โต๊ะ'),
                  Tab(text: 'ออเดอร์'),
                  Tab(text: 'ครัว'),
                  Tab(text: 'เพิ่มเติม')
                ]),
                const Expanded(
                    child: TabBarView(children: [
                  PosScreen(),
                  TablesScreen(),
                  OrdersScreen(),
                  KitchenScreen(),
                  StaffToolsScreen()
                ])),
              ]))));
        },
      );
}
