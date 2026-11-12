import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'sales_channel_scope.dart';

PreferredSizeWidget posSalesHeader(
  BuildContext context, {
  required String title,
  String? cashier,
  required bool busy,
  required bool canOpenOffline,
  required VoidCallback onOffline,
  VoidCallback? onSwitchStaff,
}) =>
    AppBar(
      toolbarHeight: math.max(
          56,
          MediaQuery.textScalerOf(context).scale(cashier == null ? 24 : 38) +
              16),
      leading: SalesChannelScope.of(context) != null
          ? SalesChannelBackButton(enabled: !busy)
          : null,
      centerTitle: false,
      title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (cashier != null)
              Tooltip(
                  message: cashier,
                  child: Text(cashier,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall)),
          ]),
      actions: [
        if (onSwitchStaff != null)
          IconButton(
              tooltip: 'เปลี่ยนผู้ใช้',
              onPressed: busy ? null : onSwitchStaff,
              icon: const Icon(Icons.person_outline)),
        PopupMenuButton<String>(
            tooltip: 'เพิ่มเติม',
            onSelected: (_) {
              if (canOpenOffline) onOffline();
            },
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'offline',
                      enabled: canOpenOffline,
                      child: const Text('ขายออฟไลน์ / บิลค้าง'))
                ]),
      ],
    );
