import 'package:flutter/material.dart';

import '../models/modifier_group.dart';
import '../services/modifier_service.dart';
import 'modifier_group_form_screen.dart';

/// List of modifier groups for a restaurant shop — e.g. "ระดับเผ็ด",
/// "ขนาด", "เพิ่มเติม". Each group can be attached to one or many
/// products from the product form.
class ModifierGroupsScreen extends StatelessWidget {
  const ModifierGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier Groups'), centerTitle: true),
      body: StreamBuilder<List<ModifierGroup>>(
        stream: ModifierService.watchAll(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snap.data ?? const [];
          if (groups.isEmpty) {
            return _EmptyState(onAdd: () => _add(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) => _GroupTile(
              group: groups[i],
              onTap: () => _edit(context, groups[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มกลุ่ม'),
      ),
    );
  }

  void _add(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ModifierGroupFormScreen(),
    ));
  }

  void _edit(BuildContext context, ModifierGroup g) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ModifierGroupFormScreen(group: g),
    ));
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.onTap});
  final ModifierGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summary = group.options.isEmpty
        ? 'ยังไม่มีตัวเลือก'
        : group.options.map((o) {
            final adj = o.priceAdjust;
            if (adj == 0) return o.name;
            final sign = adj > 0 ? '+' : '';
            return '${o.name} ($sign฿${adj.toStringAsFixed(0)})';
          }).join(' · ');

    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Text(group.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(width: 8),
          if (group.required)
            _Chip(label: 'จำเป็น', color: cs.primary),
          const SizedBox(width: 4),
          _Chip(
            label: group.multiSelect ? 'เลือกหลายอัน' : 'เลือก 1',
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(summary,
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style:
              TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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
            Icon(Icons.tune_outlined,
                size: 72, color: cs.primary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('ยังไม่มี Modifier groups',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'ใช้สำหรับให้ลูกค้าเลือก เช่น ระดับความเผ็ด, ขนาด, เพิ่มไข่ดาว',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('สร้างกลุ่มแรก'),
            ),
          ],
        ),
      ),
    );
  }
}
