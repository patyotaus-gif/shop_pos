import 'dart:async';
import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../theme/operational_colors.dart';
import '../widgets/status_badge.dart';

import '../models/restaurant_table.dart';
import '../models/table_order.dart';
import '../services/table_service.dart';
import 'table_detail_screen.dart';
import 'table_form_screen.dart';

/// Grid of restaurant tables with explicit labels and shared status colors.
/// Tap to open the order screen for that
/// table; long-press to edit/delete. Owners can switch to จัดเรียง and drop
/// one table on another to swap their places.
class TablesScreen extends StatefulWidget {
  const TablesScreen(
      {super.key, this.loadTables, this.loadOpenOrders, this.reorderTables});
  final Stream<List<RestaurantTable>> Function()? loadTables;
  final Stream<List<TableOrder>> Function()? loadOpenOrders;
  final Future<void> Function(List<String> orderedIds)? reorderTables;
  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  late Stream<List<RestaurantTable>> _tables = _load();
  Stream<List<RestaurantTable>> _load() =>
      (widget.loadTables ?? TableService.watchTables)();
  // Open bills only add the รอชำระเงิน hint; the grid still works without them.
  // Listened to once for the screen's life: the staff stream is a
  // single-subscription poll, so rebuilding the grid must not re-listen.
  Set<String> _bills = const {};
  StreamSubscription<List<TableOrder>>? _billSub;

  @override
  void initState() {
    super.initState();
    final Stream<List<TableOrder>> orders;
    try {
      orders = (widget.loadOpenOrders ?? TableService.watchOpenOrders)();
    } catch (_) {
      return; // No bill hints; the grid itself still loads.
    }
    _billSub = orders.listen((orders) {
      if (!mounted) return;
      setState(() => _bills = {
            for (final o in orders)
              if (o.billRequested) o.tableId
          });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _billSub?.cancel();
    super.dispose();
  }

  bool _arranging = false;
  // Shown immediately after a swap, until the saved order streams back.
  List<String>? _pendingOrder;

  List<RestaurantTable> _ordered(List<RestaurantTable> tables) {
    final pending = _pendingOrder;
    if (pending == null) return tables;
    final rank = {for (var i = 0; i < pending.length; i++) pending[i]: i};
    return [...tables]..sort((a, b) =>
        (rank[a.id] ?? pending.length).compareTo(rank[b.id] ?? pending.length));
  }

  Future<void> _swap(
      List<RestaurantTable> shown, String from, String to) async {
    if (from == to) return;
    final ids = shown.map((t) => t.id).toList();
    final a = ids.indexOf(from), b = ids.indexOf(to);
    if (a < 0 || b < 0) return;
    ids[a] = to;
    ids[b] = from;
    setState(() => _pendingOrder = ids);
    try {
      await (widget.reorderTables ?? TableService.reorderTables)(ids);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingOrder = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกตำแหน่งโต๊ะไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('โต๊ะ'),
        centerTitle: true,
        actions: [
          if (!AuthService.isStaff)
            TextButton.icon(
              key: const ValueKey('tables-arrange'),
              onPressed: () => setState(() {
                _arranging = !_arranging;
                if (!_arranging) _pendingOrder = null;
              }),
              icon: Icon(_arranging ? Icons.check : Icons.swap_horiz),
              label: Text(_arranging ? 'เสร็จ' : 'จัดเรียง'),
            ),
        ],
      ),
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
          final tables = _ordered(snap.data ?? const []);
          if (tables.isEmpty) {
            if (AuthService.isStaff) {
              return const Center(
                  child: Text('ยังไม่มีโต๊ะ กรุณาให้เจ้าของร้านเพิ่มโต๊ะ'));
            }
            return _EmptyState(onAdd: () => _addTable(context));
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context);
              final available = constraints.maxWidth - 32;
              final desired = ((available + 12) / 192).ceil();
              // Keep the normal two-column phone layout, but reserve more
              // width for the payment label when accessibility text grows.
              final readableWidth = math.max(124.0, scale.scale(160) - 36);
              final readable =
                  ((available + 12) / (readableWidth + 12)).floor();
              final columns = math.max(1, math.min(desired, readable));
              final cellHeight = math.max(180.0, scale.scale(130) + 48);
              final cellWidth = (available - 12 * (columns - 1)) / columns;
              Widget card(RestaurantTable table, Set<String>? bills,
                      {bool highlighted = false}) =>
                  _TableCard(
                    table: table,
                    billRequested: bills?.contains(table.id) ?? false,
                    highlighted: highlighted,
                    onTap:
                        _arranging ? null : () => _openDetail(context, table),
                    onLongPress: AuthService.isStaff || _arranging
                        ? null
                        : () => _editTable(context, table),
                  );
              return Column(children: [
                if (_arranging)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                        'ลากโต๊ะไปวางบนอีกโต๊ะเพื่อสลับตำแหน่ง แล้วกด "เสร็จ"'),
                  ),
                Expanded(
                    child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    // Reserve two lines for the status, name and section at
                    // the user's text scale, plus card padding and spacing.
                    mainAxisExtent: cellHeight,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: tables.length,
                  itemBuilder: (_, i) {
                    final table = tables[i];
                    if (!_arranging) return card(table, _bills);
                    return DragTarget<String>(
                      key: ValueKey('arrange-${table.id}'),
                      onWillAcceptWithDetails: (d) => d.data != table.id,
                      onAcceptWithDetails: (d) =>
                          _swap(tables, d.data, table.id),
                      builder: (context, candidates, _) => Draggable<String>(
                        data: table.id,
                        feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                                width: cellWidth,
                                height: cellHeight,
                                child: card(table, _bills))),
                        childWhenDragging:
                            Opacity(opacity: 0.3, child: card(table, _bills)),
                        child: card(table, _bills,
                            highlighted: candidates.isNotEmpty),
                      ),
                    );
                  },
                )),
              ]);
            },
          );
        },
      ),
      floatingActionButton: AuthService.isStaff
          ? null
          : FloatingActionButton.extended(
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
    this.billRequested = false,
    this.highlighted = false,
  });

  final RestaurantTable table;
  final bool billRequested;
  final bool highlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final occupied = table.status == TableStatus.occupied;
    final reserved = table.status == TableStatus.reserved;
    final awaitingPayment = occupied && billRequested;

    final tone = awaitingPayment
        ? OperationalTone.warning
        : occupied
            ? OperationalTone.information
            : reserved
                ? OperationalTone.warning
                : OperationalTone.neutral;
    final status = OperationalColors.of(context, tone);
    final border = highlighted
        ? cs.primary
        : occupied || reserved
            ? status.foreground
            : cs.outlineVariant;

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
            border: Border.all(
                color: border, width: occupied || highlighted ? 2 : 1),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusBadge(
                  label: awaitingPayment ? 'รอชำระเงิน' : table.status.label,
                  tone: tone,
                  icon: awaitingPayment
                      ? Icons.receipt_long_outlined
                      : reserved
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
