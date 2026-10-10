import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/operational_colors.dart';
import '../widgets/status_badge.dart';

import '../models/restaurant_table.dart';
import '../services/table_service.dart';
import 'table_detail_screen.dart';
import 'table_form_screen.dart';

/// Grid of restaurant tables with explicit labels and shared status colors.
/// Tap to open the order screen for that
/// table; long-press to edit/delete.
class TablesScreen extends StatefulWidget {
  const TablesScreen({super.key, this.loadTables});
  final Stream<List<RestaurantTable>> Function()? loadTables;
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late Stream<List<RestaurantTable>> _tables = _load();
  Stream<List<RestaurantTable>> _load() =>
      (widget.loadTables ?? TableService.watchTables)();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โต๊ะ'), centerTitle: true),
      body: StreamBuilder<List<RestaurantTable>>(
        stream: _tables,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('โหลดโต๊ะไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'),
              TextButton.icon(
                  onPressed: () => setState(() => _tables = _load()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่')),
            ]));
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tables = snap.data ?? const [];
          if (tables.isEmpty) {
            return _EmptyState(onAdd: () => _addTable(context));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context);
              final available = constraints.maxWidth - 32;
              final desired = ((available + 12) / 192).ceil();
              final readable =
                  ((available + 12) / (scale.scale(124) + 12)).floor();
              final columns = math.max(1, math.min(desired, readable));
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  // Reserve two lines for the status, name and section at
                  // the user's text scale, plus card padding and spacing.
                  mainAxisExtent: math.max(180, scale.scale(130) + 48),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: tables.length,
                itemBuilder: (_, i) => _TableCard(
                  table: tables[i],
                  onTap: () => _openDetail(context, tables[i]),
                  onLongPress: () => _editTable(context, tables[i]),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addTable(context),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มโต๊ะ'),
      ),
    );
  }

  void _openDetail(BuildContext context, RestaurantTable table) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TableDetailScreen(table: table),
    ));
  }

  void _addTable(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const TableFormScreen(),
    ));
  }

  void _editTable(BuildContext context, RestaurantTable table) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TableFormScreen(table: table),
    ));
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onTap,
    required this.onLongPress,
  });

  final RestaurantTable table;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final occupied = table.status == TableStatus.occupied;
    final reserved = table.status == TableStatus.reserved;

    final tone = occupied
        ? OperationalTone.information
        : reserved
            ? OperationalTone.warning
            : OperationalTone.neutral;
    final status = OperationalColors.of(context, tone);
    final border = occupied || reserved ? status.foreground : cs.outlineVariant;

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: occupied ? 2 : 1),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(
                  label: table.status.label,
                  tone: tone,
                  icon: reserved
                      ? Icons.event_available_outlined
                      : Icons.table_restaurant_outlined),
              const SizedBox(height: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, height: 1.3, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                      '${table.capacity} ที่นั่ง${table.section == null ? '' : ' · ${table.section}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: cs.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_restaurant_outlined,
                size: 72, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('ยังไม่มีโต๊ะ',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('เพิ่มโต๊ะแรกเพื่อเริ่มรับออเดอร์',
                style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มโต๊ะแรก'),
            ),
          ],
        ),
      ),
    );
  }
}
