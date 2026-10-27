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
                    child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(children: [
                          const Icon(Icons.badge_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                              child: FutureBuilder<Map<String, dynamic>>(
                                  future: StaffAccessService.workspace(),
                                  builder: (context, snap) {
                                    final label = snap.hasError
                                        ? operationError(snap.error!)
                                        : snap.hasData
                                            ? '${snap.data!['staffName'] ?? 'พนักงาน'} · ${StaffRole.values.firstWhere((r) => r.name == snap.data!['position'], orElse: () => StaffRole.cashier).label}'
                                            : 'กำลังตรวจสิทธิ์…';
                                    return Tooltip(
                                        message: label,
                                        child: Text(label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis));
                                  })),
                          IconButton(
                            tooltip: 'ล็อก / เปลี่ยนผู้ใช้',
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            onPressed: () =>
                                StaffAccessService.unlocked.value = false,
                            icon: const Icon(Icons.lock_outline),
                          ),
                        ]))),
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
