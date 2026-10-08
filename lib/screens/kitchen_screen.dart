import 'package:flutter/material.dart';
import '../widgets/shop_operation.dart';

import '../models/table_order.dart';
import '../services/table_service.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/settings_service.dart';
import '../services/kitchen_print_service.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen(
      {super.key,
      this.orders,
      this.onlineOrders,
      this.settings,
      this.printJobs});
  final Stream<List<TableOrder>>? orders;
  final Stream<List<ShopOrder>>? onlineOrders;
  final Stream<Map<String, dynamic>>? settings;
  final Stream<Map<String, Map<String, dynamic>>>? printJobs;
  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  late final tableStream = widget.orders ?? TableService.watchKitchenOrders();
  late final onlineStream = widget.onlineOrders ??
      (widget.orders != null
          ? Stream.value(<ShopOrder>[])
          : OrderService.watchAll());
  late final settingsStream = widget.settings ??
      (widget.orders != null
          ? Stream.value(<String, dynamic>{})
          : SettingsService.watchSettings());
  late final printStream = widget.printJobs ??
      (widget.orders != null
          ? Stream.value(<String, Map<String, dynamic>>{})
          : KitchenPrintService.watchJobs());
  bool needsPrint(Map? job, int count) =>
      job == null ||
      job['status'] != 'printed' ||
      ((job['printedKeys'] as List?)?.length ?? 0) < count;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ครัว')),
      body: StreamBuilder<Map<String, dynamic>>(
          stream: settingsStream,
          builder: (context, settings) {
            if (settings.hasError) {
              return const Center(child: Text('โหลดวิธีรับงานครัวไม่สำเร็จ'));
            }
            if (!settings.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final printer = settings.data!['kitchenOutput'] == 'printer';
            return Column(children: [
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'screen',
                            icon: Icon(Icons.monitor),
                            label: Text('จอครัว')),
                        ButtonSegment(
                            value: 'printer',
                            icon: Icon(Icons.print),
                            label: Text('เครื่องพิมพ์ครัว'))
                      ],
                      selected: {
                        printer ? 'printer' : 'screen'
                      },
                      onSelectionChanged: (v) => performShopOperation(
                          context,
                          () => SettingsService.saveSettings(
                              {'kitchenOutput': v.first})))),
              if (printer)
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        'เลือกเครื่องพิมพ์ครัวที่ระบบรองรับ แล้วตรวจรับกระดาษ • พิมพ์เฉพาะรายการใหม่ได้')),
              Expanded(
                  child: StreamBuilder<List<TableOrder>>(
                      stream: tableStream,
                      builder: (context, tables) => StreamBuilder<
                              List<ShopOrder>>(
                          stream: onlineStream,
                          builder: (context, online) => StreamBuilder<
                                  Map<String, Map<String, dynamic>>>(
                              stream: printStream,
                              builder: (context, jobs) {
                                if (tables.hasError ||
                                    online.hasError ||
                                    jobs.hasError) {
                                  return const Center(
                                      child: Text(
                                          'โหลดออเดอร์ครัวไม่สำเร็จ กรุณาตรวจการเชื่อมต่อแล้วเปิดหน้านี้ใหม่'));
                                }
                                if (!tables.hasData ||
                                    !online.hasData ||
                                    !jobs.hasData) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                final ts = tables.data!
                                    .where((o) =>
                                        o.status !=
                                            TableOrderStatus.cancelled &&
                                        o.items.any((i) =>
                                            i.kitchenStatus !=
                                            KitchenStatus.pending) &&
                                        (o.status == TableOrderStatus.open ||
                                            (printer &&
                                                needsPrint(
                                                    jobs.data!['table-${o.id}'],
                                                    o.items
                                                        .where((i) =>
                                                            i.kitchenStatus !=
                                                            KitchenStatus
                                                                .pending)
                                                        .length))))
                                    .toList();
                                final os = online.data!
                                    .where((o) =>
                                        [
                                          OrderStatus.paid,
                                          OrderStatus.accepted,
                                          OrderStatus.ready
                                        ].contains(o.status) ||
                                        (printer &&
                                            o.status == OrderStatus.completed &&
                                            needsPrint(
                                                jobs.data!['online-${o.id}'],
                                                o.items.length)))
                                    .toList()
                                  ..sort((a, b) =>
                                      (a.pickupStartAt ?? a.createdAt)
                                          .compareTo(
                                              b.pickupStartAt ?? b.createdAt));
                                if (ts.isEmpty && os.isEmpty) {
                                  return const _EmptyKitchen();
                                }
                                return ListView(
                                    padding: const EdgeInsets.all(12),
                                    children: [
                                      for (final o in os)
                                        Card(
                                            child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                          o.tableName == null
                                                              ? 'ออนไลน์ • รับกลับบ้าน'
                                                              : 'ออนไลน์ • โต๊ะ ${o.tableName}',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold)),
                                                      Text(
                                                          '${o.customerName} • ${o.status.label}'),
                                                      if (o.pickupDescription !=
                                                          null)
                                                        Text(o
                                                            .pickupDescription!),
                                                      for (final i in o.items)
                                                        ListTile(
                                                            dense: true,
                                                            title: Text(
                                                                '${i.productName} × ${i.quantity}'),
                                                            subtitle: i
                                                                    .preparationNote
                                                                    .isEmpty
                                                                ? null
                                                                : Text(i
                                                                    .preparationNote)),
                                                      if (printer)
                                                        _PrintActions(
                                                            source: 'online',
                                                            orderId: o.id,
                                                            job: jobs.data![
                                                                'online-${o.id}']),
                                                      if (o.status ==
                                                          OrderStatus.paid)
                                                        FilledButton(
                                                            onPressed: () => performShopOperation(
                                                                context,
                                                                () => OrderService
                                                                    .updateStatus(
                                                                        o.id,
                                                                        OrderStatus
                                                                            .accepted)),
                                                            child: const Text(
                                                                'เริ่มเตรียม')),
                                                      if (o.status ==
                                                          OrderStatus.accepted)
                                                        FilledButton(
                                                            onPressed: () => performShopOperation(
                                                                context,
                                                                () => OrderService
                                                                    .updateStatus(
                                                                        o.id,
                                                                        OrderStatus
                                                                            .ready)),
                                                            child: const Text(
                                                                'พร้อมรับ / เสิร์ฟแล้ว')),
                                                    ]))),
                                      for (final o in ts) ...[
                                        if (o.status == TableOrderStatus.closed)
                                          const Text(
                                              'ปิดบิลแล้ว • ตรวจว่าครัวได้รับใบงานเดิมหรือยังก่อนพิมพ์'),
                                        SizedBox(
                                            height: 360,
                                            child: _TicketCard(order: o)),
                                        if (printer)
                                          _PrintActions(
                                              source: 'table',
                                              orderId: o.id,
                                              job: jobs.data!['table-${o.id}']),
                                        const SizedBox(height: 12),
                                      ],
                                    ]);
                              })))),
            ]);
          }));
}

class _PrintActions extends StatefulWidget {
  const _PrintActions({required this.source, required this.orderId, this.job});
  final String source, orderId;
  final Map? job;
  @override
  State<_PrintActions> createState() => _PrintActionsState();
}

class _PrintActionsState extends State<_PrintActions> {
  bool busy = false;
  Future<void> print({bool reprint = false}) async {
    if (reprint || widget.job?['status'] == 'needsReview') {
      final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('ตรวจครัวก่อนพิมพ์ซ้ำ'),
                  content: const Text(
                      'อาจมีใบงานเดิมออกแล้ว แจ้งครัวว่าเป็นสำเนาเพื่อไม่ให้ทำอาหารซ้ำ'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('กลับ')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('พิมพ์สำเนา'))
                  ]));
      if (yes != true) return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await KitchenPrintService.printOrder(context,
          source: widget.source, orderId: widget.orderId, reprint: reprint);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(switch (widget.job?['status']) {
              'printed' => 'ยืนยันใบงานแล้ว',
              'printing' => 'กำลังพิมพ์ / รอยืนยัน',
              'needsReview' => 'ตรวจเครื่องพิมพ์ก่อนลองใหม่',
              _ => 'รอพิมพ์'
            }),
            FilledButton.icon(
                onPressed: busy ? null : () => print(),
                icon: const Icon(Icons.print),
                label: const Text('พิมพ์รายการใหม่')),
            TextButton(
                onPressed: busy ? null : () => print(reprint: true),
                child: const Text('พิมพ์ซ้ำ / กู้คืนงาน')),
          ]);
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.order});
  final TableOrder order;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kitchenItems = order.items
        .asMap()
        .entries
        .where((e) =>
            e.value.kitchenStatus == KitchenStatus.sent ||
            e.value.kitchenStatus == KitchenStatus.ready)
        .toList();

    final allReady =
        kitchenItems.every((e) => e.value.kitchenStatus == KitchenStatus.ready);

    return Material(
      color: allReady ? Colors.green.withValues(alpha: 0.08) : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: allReady ? Colors.green : cs.outlineVariant,
            width: allReady ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_restaurant_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('โต๊ะ ${order.tableName}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                if (allReady)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text('พร้อมเสิร์ฟทั้งหมด',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _elapsed(order.openedAt),
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: kitchenItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final entry = kitchenItems[i];
                  return _ItemRow(
                    orderId: order.id,
                    item: entry.value,
                    editable: order.status == TableOrderStatus.open,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _elapsed(DateTime opened) {
    final mins = DateTime.now().difference(opened).inMinutes;
    if (mins < 1) return 'เปิดเมื่อสักครู่';
    if (mins < 60) return 'เปิดมา $mins นาที';
    final h = mins ~/ 60;
    return 'เปิดมา $h ชม. ${mins % 60} นาที';
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.orderId,
    required this.item,
    required this.editable,
  });

  final String orderId;
  final TableOrderItem item;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = item.kitchenStatus == KitchenStatus.ready;
    final modifierLine = item.modifiers.isEmpty
        ? null
        : item.modifiers.map((m) => m.optionName).join(' · ');

    return InkWell(
      onTap: ready || !editable
          ? null
          : () => performShopOperation(
              context, () => TableService.markItemReady(orderId, item.id),
              success: 'พร้อมเสิร์ฟแล้ว'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: ready
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ready
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.amber.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('×${item.quantity}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (modifierLine != null)
                    Text('• $modifierLine',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.7))),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text('โน้ต: ${item.notes}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.deepOrange)),
                ],
              ),
            ),
            Icon(
              ready ? Icons.check_circle : Icons.local_fire_department,
              color: ready ? Colors.green : Colors.amber.shade700,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyKitchen extends StatelessWidget {
  const _EmptyKitchen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.soup_kitchen_outlined,
                size: 72, color: cs.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text('ยังไม่มีออเดอร์เข้าครัว',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'รับงานจากโต๊ะที่ส่งครัว และออเดอร์ออนไลน์ที่ร้านยืนยันรับเงินแล้ว',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
