import 'package:flutter/material.dart';

import '../models/restaurant_table.dart';
import '../services/table_service.dart';
import 'table_detail_screen.dart';
import 'table_form_screen.dart';

/// Grid of restaurant tables — color tells status (cream = available,
/// burgundy-tinted = occupied). Tap to open the order screen for that
/// table; long-press to edit/delete.
class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โต๊ะ'), centerTitle: true),
      body: StreamBuilder<List<RestaurantTable>>(
        stream: TableService.watchTables(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tables = snap.data ?? const [];
          if (tables.isEmpty) {
            return _EmptyState(onAdd: () => _addTable(context));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.95,
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

    final bg = occupied
        ? cs.primary.withValues(alpha: 0.12)
        : reserved
            ? Colors.amber.withValues(alpha: 0.12)
            : cs.surface;
    final border = occupied
        ? cs.primary
        : reserved
            ? Colors.amber.shade700
            : cs.outlineVariant;

    return Material(
      color: bg,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    Icons.table_restaurant_outlined,
                    color: occupied ? cs.primary : cs.onSurface.withValues(alpha: 0.5),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: border.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      table.status.label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: occupied ? cs.primary : cs.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table.name,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.person_outline,
                          size: 12,
                          color: cs.onSurface.withValues(alpha: 0.5)),
                      const SizedBox(width: 2),
                      Text('${table.capacity}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.6))),
                      if (table.section != null) ...[
                        const SizedBox(width: 6),
                        Text('· ${table.section}',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ],
                  ),
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
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withValues(alpha: 0.6))),
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
