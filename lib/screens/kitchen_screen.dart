import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';
import '../theme/operational_colors.dart';
import '../widgets/status_badge.dart';
import '../widgets/shop_operation.dart';

import '../models/table_order.dart';
import '../services/table_service.dart';
import '../models/order.dart';
import '../services/order_service.dart';
import '../services/settings_service.dart';
import '../services/kitchen_print_service.dart';
import '../services/cash_session_service.dart';
import '../utils/operation_error.dart';
import 'table_detail_screen.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen(
      {super.key,
      this.orders,
      this.onlineOrders,
      this.settings,
      this.printJobs,
      this.lastClosedAt,
      this.saveOutput,
      this.markReady,
      this.updateOnlineStatus,
      this.now});
  final Stream<List<TableOrder>>? orders;
  final Stream<List<ShopOrder>>? onlineOrders;
  final Stream<Map<String, dynamic>>? settings;
  final Stream<Map<String, Map<String, dynamic>>>? printJobs;
  final Stream<DateTime?>? lastClosedAt;
  final Future<void> Function(String)? saveOutput;
  final Future<void> Function(String, String)? markReady;
  final Future<void> Function(String, OrderStatus)? updateOnlineStatus;
  final DateTime Function()? now;
  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  bool _savingOutput = false;
  bool _showHistory = false;
  DateTime? _previousRoundsForClose;
  Future<void> _changeOutput(Set<String> selection) async {
    if (_savingOutput) return;
    setState(() => _savingOutput = true);
    try {
      await performShopOperation(
          context,
          () => (widget.saveOutput ??
              SettingsService.saveKitchenOutput)(selection.first),
          timeout: const Duration(seconds: 20),
          message: 'กำลังบันทึกวิธีรับงานครัว',
          success: 'บันทึกวิธีรับงานครัวแล้ว');
    } finally {
      if (mounted) setState(() => _savingOutput = false);
    }
  }

  late Stream<List<TableOrder>> tableStream;
  late Stream<List<ShopOrder>> onlineStream;
  late Stream<Map<String, dynamic>> settingsStream;
  late Stream<Map<String, Map<String, dynamic>>> printStream;
  late Stream<DateTime?> closeStream;
  int _streamKey = 0;
  Timer? _dayTimer;
  @override
  void initState() {
    super.initState();
    _bindStreams();
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    super.dispose();
  }

  void _bindStreams() {
    tableStream = widget.orders ?? TableService.watchKitchenOrders();
    onlineStream = widget.onlineOrders ??
        (widget.orders != null
            ? Stream.value(<ShopOrder>[])
            : OrderService.watchAll());
    settingsStream = widget.settings ??
        (widget.orders != null
            ? Stream.value(<String, dynamic>{})
            : SettingsService.watchSettings());
    printStream = widget.printJobs ??
        (widget.orders != null
            ? Stream.value(<String, Map<String, dynamic>>{})
            : AuthService.isStaff
                ? Stream.value(<String, Map<String, dynamic>>{})
                : KitchenPrintService.watchJobs());
    closeStream = widget.lastClosedAt ??
        (widget.orders != null
            ? Stream<DateTime?>.value(null)
            : AuthService.isStaff
                ? Stream<DateTime?>.value(null)
                : CashSessionService.watchLastClosedAt());
  }

  bool needsPrint(Map? job, int count) =>
      job == null ||
      !['printed', 'sent'].contains(job['status']) ||
      ((job['printedKeys'] as List?)?.length ?? 0) < count;
  bool unfinished(TableOrder o) =>
      o.items.any((i) => i.kitchenStatus == KitchenStatus.sent);

  Widget _loadError(String message) => Center(
          child: SingleChildScrollView(
              child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          const Text('หากการเชื่อมต่อขัดข้อง ระบบจะลองเชื่อมต่อใหม่'),
          TextButton.icon(
              onPressed: () => setState(() {
                    _bindStreams();
                    _streamKey++;
                  }),
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่')),
        ]),
      )));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ครัว')),
        body: StreamBuilder<Map<String, dynamic>>(
          key: ValueKey(_streamKey),
          stream: settingsStream,
          builder: (context, settings) {
            final printer = !AuthService.isStaff &&
                settings.data?['kitchenOutput'] == 'printer';
            return Column(children: [
              if (!AuthService.isStaff)
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
                              label: Text('เครื่องพิมพ์ครัว')),
                        ],
                        selected: {
                          printer ? 'printer' : 'screen'
                        },
                        onSelectionChanged: _savingOutput ||
                                settings.hasError ||
                                !settings.hasData
                            ? null
                            : _changeOutput)),
              if (printer)
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        'เลือกเครื่องพิมพ์ครัวที่ระบบรองรับ แล้วตรวจรับกระดาษ • พิมพ์เฉพาะรายการใหม่ได้')),
              Expanded(
                  child: StreamBuilder<DateTime?>(
                      stream: closeStream,
                      builder: (context, closing) {
                        return StreamBuilder<List<TableOrder>>(
                            stream: tableStream,
                            builder: (context, tables) => StreamBuilder<
                                    List<ShopOrder>>(
                                stream: onlineStream,
                                builder: (context, online) => StreamBuilder<
                                        Map<String, Map<String, dynamic>>>(
                                    stream: printStream,
                                    builder: (context, jobs) {
                                      // Keep all subscriptions mounted across errors. A recovered
                                      // settings stream must not resubscribe to consumed streams.
                                      if (settings.hasError) {
                                        return _loadError(
                                            'โหลดวิธีรับงานครัวไม่สำเร็จ');
                                      }
                                      if (closing.hasError) {
                                        return _loadError(
                                            'โหลดรอบปิดยอดไม่สำเร็จ กรุณาเปิดหน้านี้ใหม่ก่อนตรวจคิวพิมพ์');
                                      }
                                      if (tables.hasError ||
                                          online.hasError ||
                                          jobs.hasError) {
                                        return _loadError(
                                            'โหลดออเดอร์ครัวไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ');
                                      }
                                      if (!settings.hasData ||
                                          closing.connectionState ==
                                              ConnectionState.waiting ||
                                          !tables.hasData ||
                                          !online.hasData ||
                                          !jobs.hasData) {
                                        return const Center(
                                            child: CircularProgressIndicator());
                                      }
                                      final cutoff = closing.data;
                                      final showPrevious = cutoff != null &&
                                          _previousRoundsForClose == cutoff;
                                      bool oldTable(TableOrder o) =>
                                          !unfinished(o) &&
                                          o.status == TableOrderStatus.closed &&
                                          cutoff != null &&
                                          !(o.closedAt ?? o.openedAt)
                                              .isAfter(cutoff);
                                      bool oldOnline(ShopOrder o) =>
                                          o.status == OrderStatus.completed &&
                                          cutoff != null &&
                                          !(o.statusUpdatedAt ??
                                                  o.pickupEndAt ??
                                                  o.paidAt ??
                                                  o.createdAt)
                                              .isAfter(cutoff);
                                      final eligibleTables = tables.data!
                                          .where((o) =>
                                              o.status !=
                                                  TableOrderStatus.cancelled &&
                                              o.items.any((i) =>
                                                  i.kitchenStatus !=
                                                  KitchenStatus.pending) &&
                                              (o.status ==
                                                      TableOrderStatus.open ||
                                                  unfinished(o) ||
                                                  (printer &&
                                                      needsPrint(
                                                          jobs.data![
                                                              'table-${o.id}'],
                                                          o.items
                                                              .where((i) =>
                                                                  i.kitchenStatus !=
                                                                  KitchenStatus
                                                                      .pending)
                                                              .length))))
                                          .toList();
                                      final eligibleOnline = online.data!
                                          .where((o) =>
                                              [
                                                OrderStatus.paid,
                                                OrderStatus.accepted,
                                                OrderStatus.ready
                                              ].contains(o.status) ||
                                              (printer &&
                                                  o.status ==
                                                      OrderStatus.completed &&
                                                  needsPrint(
                                                      jobs.data![
                                                          'online-${o.id}'],
                                                      o.items.length)))
                                          .toList();
                                      final previousCount = eligibleTables
                                              .where(oldTable)
                                              .length +
                                          eligibleOnline
                                              .where(oldOnline)
                                              .length;
                                      final ts = eligibleTables
                                          .where((o) =>
                                              showPrevious || !oldTable(o))
                                          .toList();
                                      final os = eligibleOnline
                                          .where((o) =>
                                              showPrevious || !oldOnline(o))
                                          .toList();
                                      final historyCount = ts
                                              .where((o) =>
                                                  o.status ==
                                                      TableOrderStatus.closed &&
                                                  !unfinished(o))
                                              .length +
                                          os
                                              .where((o) =>
                                                  o.status ==
                                                  OrderStatus.completed)
                                              .length;
                                      if (ts.isEmpty &&
                                          os.isEmpty &&
                                          previousCount == 0) {
                                        return const _EmptyKitchen();
                                      }
                                      final active =
                                          <({DateTime at, Widget child})>[];
                                      final ready =
                                          <({DateTime at, Widget child})>[];
                                      final future =
                                          <({DateTime at, Widget child})>[];
                                      final history = <Widget>[];
                                      final now =
                                          (widget.now?.call() ?? DateTime.now())
                                              .toUtc()
                                              .add(const Duration(hours: 7));
                                      bool laterDay(DateTime date) {
                                        final thai = date
                                            .toUtc()
                                            .add(const Duration(hours: 7));
                                        return DateTime.utc(
                                                thai.year, thai.month, thai.day)
                                            .isAfter(DateTime.utc(
                                                now.year, now.month, now.day));
                                      }

                                      for (final o in ts) {
                                        final card = Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              _TicketCard(
                                                  order: o,
                                                  markReady: widget.markReady ??
                                                      TableService
                                                          .markItemReady),
                                              if (printer)
                                                _PrintActions(
                                                    source: 'table',
                                                    orderId: o.id,
                                                    job: jobs.data![
                                                        'table-${o.id}']),
                                              const SizedBox(height: 12),
                                            ]);
                                        if (o.status ==
                                                TableOrderStatus.closed &&
                                            !unfinished(o)) {
                                          history.add(card);
                                        } else {
                                          (unfinished(o) ? active : ready).add(
                                              (at: o.openedAt, child: card));
                                        }
                                      }
                                      for (final o in os) {
                                        final card = _onlineTicket(o, printer,
                                            jobs.data!['online-${o.id}']);
                                        if (o.status == OrderStatus.completed) {
                                          history.add(card);
                                        } else {
                                          final group = o.status ==
                                                  OrderStatus.ready
                                              ? ready
                                              : (o.status == OrderStatus.paid &&
                                                      o.pickupStartAt != null &&
                                                      laterDay(
                                                          o.pickupStartAt!))
                                                  ? future
                                                  : active;
                                          group.add((
                                            at: o.pickupStartAt ?? o.createdAt,
                                            child: card
                                          ));
                                        }
                                      }
                                      for (final group in [
                                        active,
                                        ready,
                                        future
                                      ]) {
                                        group.sort(
                                            (a, b) => a.at.compareTo(b.at));
                                      }
                                      return ListView(
                                          padding: const EdgeInsets.all(12),
                                          children: [
                                            if (previousCount > 0)
                                              SwitchListTile(
                                                  title: Text(
                                                      'ดูใบงานรอบก่อน ($previousCount)'),
                                                  subtitle: Text(
                                                      'ปิดยอดล่าสุด ${DateFormat('dd/MM/yyyy HH:mm').format(cutoff!.toLocal())} น. • ตรวจใบเดิมก่อนพิมพ์ซ้ำ'),
                                                  value: showPrevious,
                                                  onChanged: (v) => setState(() =>
                                                      _previousRoundsForClose =
                                                          v ? cutoff : null)),
                                            if (historyCount > 0 &&
                                                !showPrevious)
                                              SwitchListTile(
                                                  title: Text(
                                                      'ใบงานที่ปิดบิลหรือเสร็จแล้ว ($historyCount)'),
                                                  subtitle: const Text(
                                                      'ยังไม่ยืนยันพิมพ์ ไม่ใช่บิลค้างชำระ'),
                                                  value: _showHistory,
                                                  onChanged: (v) => setState(
                                                      () => _showHistory = v)),
                                            if (active.isEmpty && ready.isEmpty)
                                              const Padding(
                                                  padding: EdgeInsets.all(12),
                                                  child: Text(
                                                      'ไม่มีงานครัวที่กำลังดำเนินการ')),
                                            if (active.isNotEmpty)
                                              Text(
                                                  'งานที่ต้องเตรียม (${active.length})',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                            ...active.map((e) => e.child),
                                            if (ready.isNotEmpty)
                                              Text(
                                                  'พร้อมรับ / พร้อมเสิร์ฟ (${ready.length})',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                            ...ready.map((e) => e.child),
                                            if (future.isNotEmpty)
                                              ExpansionTile(
                                                  title: Text(
                                                      'นัดรับวันถัดไป (${future.length})'),
                                                  subtitle: const Text(
                                                      'ตรวจวันและเวลานัดก่อนเริ่มเตรียม'),
                                                  children: future
                                                      .map((e) => e.child)
                                                      .toList()),
                                            if (_showHistory || showPrevious)
                                              ...history,
                                          ]);
                                    })));
                      })),
            ]);
          },
        ),
      );

  Widget _onlineTicket(ShopOrder o, bool printer, Map<String, dynamic>? job) =>
      Card(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              o.tableName == null
                  ? 'ออนไลน์ • รับกลับบ้าน'
                  : 'ออนไลน์ • โต๊ะ ${o.tableName}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('เลขออเดอร์ ${o.displayNumber}'),
          Text('${o.customerName} • ${o.status.label}'),
          Text(
              'รับออเดอร์ ${DateFormat('dd/MM/yyyy HH:mm').format(o.createdAt.toLocal())} น.'),
          if (o.pickupDescription != null) Text(o.pickupDescription!),
          for (final i in o.items)
            ListTile(
                dense: true,
                title: Text('${i.productName} × ${i.quantity}'),
                subtitle:
                    i.preparationNote.isEmpty ? null : Text(i.preparationNote)),
          if (printer) _PrintActions(source: 'online', orderId: o.id, job: job),
          if ([OrderStatus.paid, OrderStatus.accepted, OrderStatus.ready]
              .contains(o.status))
            FilledButton(
                onPressed: () => performShopOperation(
                    context,
                    () => (widget.updateOnlineStatus ??
                            OrderService.updateStatus)(
                        o.id,
                        o.status == OrderStatus.paid
                            ? OrderStatus.accepted
                            : o.status == OrderStatus.accepted
                                ? OrderStatus.ready
                                : OrderStatus.completed),
                    timeout: const Duration(seconds: 25),
                    success: o.status == OrderStatus.ready
                        ? 'ส่งมอบออเดอร์แล้ว'
                        : 'บันทึกแล้ว'),
                child: Text(o.status == OrderStatus.paid
                    ? 'เริ่มเตรียม'
                    : o.status == OrderStatus.accepted
                        ? 'พร้อมรับ / เสิร์ฟแล้ว'
                        : 'ส่งมอบแล้ว / เสร็จสิ้น')),
        ]),
      ));
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
              'sent' => 'ส่งข้อมูลแล้ว • ตรวจใบที่เครื่องพิมพ์',
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
  const _TicketCard({required this.order, required this.markReady});
  final TableOrder order;
  final Future<void> Function(String, String) markReady;

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
    final success = OperationalColors.of(context, OperationalTone.success);

    return Material(
      color: allReady ? success.background : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: allReady ? success.foreground : cs.outlineVariant,
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
              ],
            ),
            const SizedBox(height: 4),
            if (allReady)
              const StatusBadge(
                  label: 'พร้อมเสิร์ฟทั้งหมด',
                  tone: OperationalTone.success,
                  icon: Icons.check_circle_outline),
            Text(
              'รับออเดอร์ ${DateFormat('dd/MM/yyyy HH:mm').format(order.openedAt.toLocal())} น.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            if (order.status == TableOrderStatus.closed)
              Text(
                  allReady
                      ? 'ปิดบิลแล้ว • ประวัติใบงานครัว'
                      : 'ชำระแล้ว • ยังมีอาหารที่ต้องเตรียม',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const Divider(height: 16),
            if (order.status == TableOrderStatus.open)
              TextButton.icon(
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('ไปที่บิลโต๊ะ / ปิดโต๊ะ'),
                onPressed: () async {
                  try {
                    final table = await runShopOperation(
                        context, () => TableService.getTable(order.tableId),
                        timeout: const Duration(seconds: 15),
                        message: 'กำลังเปิดบิลโต๊ะ');
                    if (table == null) throw StateError('ไม่พบโต๊ะนี้');
                    if (context.mounted) {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TableDetailScreen(table: table)));
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(operationError(error))));
                    }
                  }
                },
              ),
            for (final entry in kitchenItems) ...[
              _ItemRow(
                orderId: order.id,
                item: entry.value,
                editable: order.status != TableOrderStatus.cancelled,
                markReady: markReady,
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.orderId,
    required this.item,
    required this.editable,
    required this.markReady,
  });

  final String orderId;
  final TableOrderItem item;
  final bool editable;
  final Future<void> Function(String, String) markReady;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = item.kitchenStatus == KitchenStatus.ready;
    final status = OperationalColors.of(
        context, ready ? OperationalTone.success : OperationalTone.warning);
    final modifierLine = item.modifiers.isEmpty
        ? null
        : item.modifiers.map((m) => m.optionName).join(' · ');

    return InkWell(
      onTap: ready || !editable
          ? null
          : () => performShopOperation(
              context, () => markReady(orderId, item.id),
              timeout: const Duration(seconds: 20), success: 'พร้อมเสิร์ฟแล้ว'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: status.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: status.foreground.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 32),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('×${item.quantity}',
                  style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
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
                            fontSize: 14, color: cs.onSurfaceVariant)),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text('โน้ต: ${item.notes}',
                        style:
                            TextStyle(fontSize: 14, color: status.foreground)),
                ],
              ),
            ),
            Icon(
              ready ? Icons.check_circle : Icons.local_fire_department,
              color: status.foreground,
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
