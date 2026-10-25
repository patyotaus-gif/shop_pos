import '../widgets/stock_quantity_dialog.dart';
import 'package:flutter/material.dart';
import '../widgets/compact_action.dart';
import '../widgets/shop_operation.dart';
import '../utils/operation_error.dart';

import '../models/restaurant_table.dart';
import '../models/table_order.dart';
import '../models/sale.dart';
import '../services/settings_service.dart';
import '../services/table_service.dart';
import '../services/staff_access_service.dart';
import '../services/table_promotion_controller.dart';
import '../services/quantity_edit_queue.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/product_picker_sheet.dart';
import '../widgets/split_bill_sheet.dart';
import '../widgets/table_promotion_dialog.dart';
import 'sale_receipt_screen.dart';
import 'kitchen_screen.dart';

/// Order workflow for a single table. Three states:
/// 1. No open tab → big "เปิดออเดอร์" CTA
/// 2. Tab open, empty → "เพิ่มสินค้า" prompt + add button
/// 3. Tab open with items → cart list + add/close/cancel actions
class TableDetailScreen extends StatelessWidget {
  const TableDetailScreen({super.key, required this.table});
  final RestaurantTable table;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('โต๊ะ ${table.name}'),
        centerTitle: true,
        actions: [
          TextButton.icon(
            label: const Text('ตรวจสถานะโต๊ะ'),
            icon: const Icon(Icons.sync, size: 18),
            onPressed: () async {
              String? status;
              final ok = await performShopOperation(context, () async {
                status = await TableService.reconcileTable(table.id);
              },
                  message: 'กำลังตรวจบิลและสถานะโต๊ะ',
                  success: 'ตรวจสถานะโต๊ะแล้ว');
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(status == 'available'
                        ? 'โต๊ะว่างแล้ว ประวัติบิลยังอยู่ครบ'
                        : 'โต๊ะยังมีบิลเปิดอยู่ กรุณาชำระเงินและปิดบิล หรือยกเลิกพร้อมระบุเหตุผล')));
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<TableOrder?>(
        stream: TableService.watchOpenOrderForTable(table.id),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text(operationError(snap.error!)));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = snap.data;
          if (order == null) {
            return _OpenOrderPrompt(table: table);
          }
          return TableOrderView(order: order);
        },
      ),
    );
  }
}

class _OpenOrderPrompt extends StatefulWidget {
  const _OpenOrderPrompt({required this.table});
  final RestaurantTable table;

  @override
  State<_OpenOrderPrompt> createState() => _OpenOrderPromptState();
}

class _OpenOrderPromptState extends State<_OpenOrderPrompt> {
  bool _opening = false;

  Future<void> _openOrder() async {
    setState(() => _opening = true);
    try {
      await TableService.openOrder(widget.table);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(operationError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.restaurant_outlined,
                size: 72, color: cs.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            const Text('ยังไม่พบบิลเปิดของโต๊ะนี้',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'เปิดออเดอร์เพื่อเริ่มรับสินค้า หากสถานะไม่ตรงให้กดตรวจสถานะโต๊ะที่มุมบน',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _opening ? null : _openOrder,
              icon: _opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('เปิดออเดอร์'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TableOrderView extends StatefulWidget {
  const TableOrderView(
      {super.key,
      required this.order,
      this.changeQuantity,
      this.syncPromotions,
      this.loadServiceCharge});
  final TableOrder order;
  final Future<void> Function(String, String, num, num)? changeQuantity;
  final Future<double> Function()? loadServiceCharge;
  final SyncTablePromotion? syncPromotions;

  @override
  State<TableOrderView> createState() => _OpenOrderViewState();
}

class _OpenOrderViewState extends State<TableOrderView> {
  bool _closing = false;
  bool _paymentOpen = false;
  bool _sending = false;
  late final TablePromotionController _promotions;
  TableOrder get _order => _promotions.order;
  final Map<String, num> _quantityPreview = {};
  final Map<String, QuantityEditQueue> _quantityQueues = {};
  @override
  void dispose() {
    _promotions.dispose();
    for (final queue in _quantityQueues.values) {
      queue.dispose();
    }
    super.dispose();
  }

  bool get _busy => _closing || _sending || _quantityPreview.isNotEmpty;
  double get _subtotal => _order.items.fold(
      0.0,
      (sum, item) =>
          sum +
          (item.unitPrice * (_quantityPreview[item.id] ?? item.quantity) * 100)
                  .round() /
              100);
  double _serviceChargePercent = 0;

  @override
  void initState() {
    super.initState();
    _promotions = TablePromotionController(
        widget.order, widget.syncPromotions ?? TableService.syncPromotions)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    (widget.loadServiceCharge ?? SettingsService.getServiceChargePercent)()
        .then((pct) {
      if (mounted) setState(() => _serviceChargePercent = pct);
    });
  }

  @override
  void didUpdateWidget(covariant TableOrderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order != widget.order) _promotions.update(widget.order);
  }

  Future<void> _addItem() async {
    await showTableProductPicker(context, orderId: _order.id);
  }

  Future<void> _changeQty(int index, num delta) async {
    final item = _order.items[index];
    if (item.isGift) return;
    if (!_closing && !_sending && item.kitchenStatus == KitchenStatus.pending) {
      final queue = _quantityQueues.putIfAbsent(item.id, () {
        late QuantityEditQueue value;
        value = QuantityEditQueue(
            quantity: item.quantity,
            save: (expected, target) =>
                widget.changeQuantity
                    ?.call(_order.id, item.id, target, expected) ??
                TableService.setItemQuantity(_order.id, item.id, target,
                    expectedQuantity: expected),
            onChanged: () {
              if (!mounted) return;
              setState(() {
                if (value.busy) {
                  _quantityPreview[item.id] = value.target;
                } else {
                  _quantityPreview.remove(item.id);
                }
              });
            },
            onError: (error) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(operationError(error))));
              }
            });
        return value;
      });
      queue.reconcile(item.quantity);
      queue.change(delta);
      return;
    }
    if (_closing || _sending || _quantityPreview.containsKey(item.id)) return;
    final pending = item.kitchenStatus == KitchenStatus.pending;
    setState(() => _quantityPreview[item.id] =
        pending ? item.quantity + delta : item.quantity);
    try {
      if (widget.changeQuantity != null) {
        await widget.changeQuantity!(
            _order.id, item.id, item.quantity + delta, item.quantity);
      } else {
        await TableService.setItemQuantity(
            _order.id, item.id, item.quantity + delta,
            expectedQuantity: item.quantity);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    } finally {
      if (mounted) setState(() => _quantityPreview.remove(item.id));
    }
  }

  double get _discount => _order.promotionCurrent
      ? (_order.promotion!['discountMinor'] as num).toDouble() / 100
      : 0;
  double get _serviceCharge => _order.promotionCurrent
      ? (_order.promotion!['serviceMinor'] as num).toDouble() / 100
      : _serviceChargePercent <= 0
          ? 0
          : ((_subtotal - _discount) * _serviceChargePercent).round() / 100;
  double get _grandTotal => _subtotal - _discount + _serviceCharge;
  Future<TableOrder?> _reviewPromotions() async {
    if (_busy || _promotions.busy) return null;
    setState(() => _closing = true);
    try {
      final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => TablePromotionDialog(
                initialCode:
                    _order.promotion?['coupon']?['code'] as String? ?? '',
                load: (code) =>
                    TableService.promotions(_order.id, couponCode: code),
                apply: (code, revision) async {
                  await TableService.promotions(_order.id,
                      action: 'apply', couponCode: code, revision: revision);
                },
              ));
      if (saved == true) {
        final fresh = await TableService.readOrder(_order.id);
        _promotions.update(fresh);
        return fresh;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(e))));
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
    return null;
  }

  bool get _hasPendingItems =>
      _order.items.any((i) => i.kitchenStatus == KitchenStatus.pending);

  Future<void> _sendToKitchen() async {
    if (_busy) return;
    setState(() => _sending = true);
    try {
      final sent = await _promotions.ensure(send: true);
      if (sent == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('ส่งเข้าคิวครัวแล้ว'),
            action: SnackBarAction(
                label: 'จอครัว / พิมพ์',
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const KitchenScreen()))),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งครัวไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close({int splitCount = 1}) async {
    if (_busy) return;
    if (_order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรายการในออเดอร์')),
      );
      return;
    }
    setState(() => _closing = true);
    var confirmedOrder = await _promotions.ensure();
    if (confirmedOrder == null || !mounted) {
      if (mounted) setState(() => _closing = false);
      return;
    }
    if (confirmedOrder.items
        .any((i) => i.kitchenStatus == KitchenStatus.pending)) {
      confirmedOrder = await _promotions.ensure(send: true);
      if (confirmedOrder == null || !mounted) {
        if (mounted) setState(() => _closing = false);
        return;
      }
    }
    final payableOrder = confirmedOrder;
    final promotion = confirmedOrder.promotion!;
    final confirmedServiceCharge =
        (promotion['serviceChargePercent'] as num).toDouble();
    setState(() => _paymentOpen = true);
    final result = await showPaymentSheet(context,
        total: (promotion['totalMinor'] as num).toDouble() / 100,
        summary: [
          ...payableOrder.items.map((i) => '${i.productName} × ${i.quantity}'),
          'ค่าสินค้า ฿${((promotion['subtotalMinor'] as num) / 100).toStringAsFixed(2)}',
          'ส่วนลด ฿${((promotion['discountMinor'] as num) / 100).toStringAsFixed(2)}',
          'ค่าบริการ ฿${((promotion['serviceMinor'] as num) / 100).toStringAsFixed(2)}',
        ].join('\n'),
        initialChannel: SalesChannel.dineIn);
    if (mounted) setState(() => _paymentOpen = false);
    if (result == null || !mounted) {
      if (mounted) setState(() => _closing = false);
      return;
    }
    try {
      final navigator = Navigator.of(context);
      final saleId = await runShopOperation(
          context,
          () => TableService.closeOrder(
                order: payableOrder,
                paid: result.paid,
                discount: (promotion['discountMinor'] as num).toDouble() / 100,
                paymentMethod: result.method,
                salesChannel: result.salesChannel,
                serviceChargePercent: confirmedServiceCharge,
                splitCount: splitCount,
              ));
      if (navigator.mounted) {
        navigator.pushReplacement(MaterialPageRoute<void>(
            builder: (_) => SaleReceiptScreen(saleId: saleId)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _closing = false);
        _promotions.error = e;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(operationError(e))),
        );
      }
    }
  }

  Future<void> _split() async {
    if (_busy) return;
    if (_order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรายการในออเดอร์')),
      );
      return;
    }
    setState(() => _closing = true);
    final fresh = await _promotions.ensure();
    if (!mounted) return;
    setState(() => _closing = false);
    if (fresh == null) return;
    final n = await showSplitBillSheet(context,
        total: (fresh.promotion!['totalMinor'] as num).toDouble() / 100);
    if (n == null || !mounted) return;
    await _close(splitCount: n);
  }

  Future<void> _keepPreparedGifts() async {
    var reason = '';
    final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('คงของแถมที่ส่งครัวแล้ว'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'ของแถมยังให้ลูกค้าฟรีและตัดสต๊อกตามจริง ส่วนสินค้าอื่นคิดตามรายการปัจจุบัน ไม่ยกเลิกทั้งบิล'),
                TextField(
                    onChanged: (value) => reason = value,
                    maxLength: 500,
                    decoration: const InputDecoration(
                        labelText: 'เหตุผล เช่น ร้านยินดีให้ของแถมเดิม')),
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('กลับ')),
                FilledButton(
                    onPressed: () {
                      if (reason.trim().isNotEmpty) {
                        Navigator.pop(ctx, reason.trim());
                      }
                    },
                    child: const Text('คงของแถมฟรี'))
              ],
            ));
    if (text == null || !mounted) return;
    setState(() => _closing = true);
    await _promotions.ensure(keepPreparedGifts: true, reason: text);
    if (mounted) setState(() => _closing = false);
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    bool consumePrepared = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
                title: const Text('ยกเลิกออเดอร์?'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('เก็บประวัติยกเลิกไว้โดยไม่สร้างยอดขาย'),
                  TextField(
                      controller: reason,
                      maxLength: 500,
                      decoration:
                          const InputDecoration(labelText: 'เหตุผลที่ยกเลิก')),
                  CheckboxListTile(
                      value: consumePrepared,
                      title: const Text('รายการที่ส่งครัวเริ่มทำแล้ว'),
                      subtitle: const Text(
                          'ตัดสินค้าและวัตถุดิบของรายการที่ส่งครัวเป็นของเสีย หากยังไม่เริ่มทำให้เอาเครื่องหมายออก'),
                      onChanged: (value) => setDialogState(
                          () => consumePrepared = value ?? true)),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('กลับ')),
                  FilledButton(
                    onPressed: () {
                      if (reason.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, true);
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('ยกเลิกออเดอร์'),
                  ),
                ],
              )),
    );
    if (confirm != true || !mounted) return;
    try {
      await runShopOperation(
          context,
          () => TableService.cancelOrder(_order,
              reason: reason.text.trim(), consumePrepared: consumePrepared));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final order = _order;
    final empty = order.items.isEmpty;

    return PopScope(
        canPop: !_busy,
        child: Column(
          children: [
            Expanded(
              child: empty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_shopping_cart_outlined,
                                size: 56,
                                color: cs.onSurface.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            Text('ยังไม่มีรายการ',
                                style: TextStyle(
                                    color:
                                        cs.onSurface.withValues(alpha: 0.6))),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: order.items.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: cs.outlineVariant),
                      itemBuilder: (_, i) {
                        final original = order.items[i];
                        final item = original.copyWith(
                            quantity: _quantityPreview[original.id]);
                        final modifierLine = item.modifiers.isEmpty
                            ? null
                            : item.modifiers.map((m) {
                                if (m.priceAdjust == 0) return m.optionName;
                                final sign = m.priceAdjust > 0 ? '+' : '';
                                return '${m.optionName} ($sign฿${m.priceAdjust.toStringAsFixed(0)})';
                              }).join(' · ');
                        return ListTile(
                          title: Text(item.productName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _KitchenStatusChip(status: item.kitchenStatus),
                              if (modifierLine != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('• $modifierLine',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.primary
                                              .withValues(alpha: 0.85))),
                                ),
                              if (item.notes != null && item.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text('โน้ต: ${item.notes}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: cs.onSurface
                                              .withValues(alpha: 0.7))),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '฿${item.unitPrice.toStringAsFixed(2)} × ${item.quantity} = ฿${item.subtotal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.6)),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: (item.isGift ||
                                        _closing ||
                                        _sending ||
                                        (item.kitchenStatus !=
                                                KitchenStatus.pending &&
                                            _quantityPreview
                                                .containsKey(item.id)))
                                    ? null
                                    : () => _changeQty(i, -1),
                              ),
                              TextButton(
                                  onPressed: _busy || item.isGift
                                      ? null
                                      : () async {
                                          final q = await showStockQuantity(
                                              context,
                                              unit: item.unit,
                                              weighed: item.isWeighed,
                                              initial: item.quantity);
                                          if (q != null && mounted) {
                                            await _changeQty(
                                                i, q - item.quantity);
                                          }
                                        },
                                  child: Text(
                                      item.isWeighed
                                          ? '${item.quantity} ${item.unit}'
                                          : '${item.quantity}',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700))),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: (item.isGift ||
                                        _closing ||
                                        _sending ||
                                        (item.kitchenStatus !=
                                                KitchenStatus.pending &&
                                            _quantityPreview
                                                .containsKey(item.id)))
                                    ? null
                                    : () => _changeQty(i, 1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.55),
                  child: SingleChildScrollView(
                      child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border(top: BorderSide(color: cs.outlineVariant)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_quantityPreview.isNotEmpty || _promotions.busy)
                          const LinearProgressIndicator(),
                        TextButton.icon(
                          onPressed: !StaffAccessService.can('discount') ||
                                  _busy ||
                                  empty ||
                                  _promotions.busy
                              ? null
                              : _reviewPromotions,
                          icon:
                              const Icon(Icons.local_offer_outlined, size: 18),
                          label: const Text('คูปอง / รายละเอียดส่วนลด'),
                        ),
                        if (_promotions.busy)
                          const Text('กำลังคำนวณโปรโมชั่นอัตโนมัติ'),
                        if (_promotions.error != null) ...[
                          Text(operationError(_promotions.error!),
                              style: TextStyle(color: cs.error)),
                          Wrap(children: [
                            TextButton(
                                onPressed: _busy || _promotions.busy
                                    ? null
                                    : () => _promotions.ensure(),
                                child: const Text('ลองอีกครั้ง')),
                            if (operationError(_promotions.error!)
                                .contains('ของแถมส่งครัวแล้ว'))
                              TextButton(
                                  onPressed: _busy || _promotions.busy
                                      ? null
                                      : _keepPreparedGifts,
                                  child: const Text('คงของแถมที่ส่งครัวแล้ว')),
                          ]),
                        ],
                        if (_discount > 0)
                          Text('ส่วนลด ฿${_discount.toStringAsFixed(2)}'),
                        // Items subtotal — show it explicitly only when a service
                        // charge is being added on top; otherwise the running
                        // "ยอดรวม" is clear enough on its own.
                        if (_serviceCharge > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ค่าสินค้า',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.6))),
                              Text('฿${_subtotal.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.7))),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  'Service ${_serviceChargePercent.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.6))),
                              Text('฿${_serviceCharge.toStringAsFixed(2)}',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.7))),
                            ],
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ยอดรวม',
                                style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        cs.onSurface.withValues(alpha: 0.7))),
                            Flexible(
                                child: Text(
                                    _quantityPreview.isNotEmpty ||
                                            !order.promotionCurrent
                                        ? 'กำลังตรวจยอด'
                                        : '฿${_grandTotal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: cs.primary))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ActionButtons(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _addItem,
                              icon: const Icon(Icons.add),
                              label: const Text('เพิ่มสินค้า'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                            if (_hasPendingItems)
                              FilledButton.tonalIcon(
                                onPressed: _busy ? null : _sendToKitchen,
                                icon: const Icon(Icons.soup_kitchen_outlined),
                                label: Text(
                                    'ส่งครัวพร้อมของแถม (${_order.items.where((i) => i.kitchenStatus == KitchenStatus.pending).fold<num>(0, (sum, i) => sum + i.quantity)})'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 14),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ActionButtons(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy || empty ? null : _split,
                              icon: const Icon(Icons.call_split),
                              label: const Text('แยกบิล'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                            FilledButton.icon(
                              key: const ValueKey('table-payment'),
                              onPressed: _busy || empty ? null : () => _close(),
                              icon: _closing && !_paymentOpen
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.point_of_sale_outlined),
                              label: Text(
                                  _hasPendingItems || !order.promotionCurrent
                                      ? 'ส่งครัวและรับชำระ'
                                      : 'รับชำระเงิน'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        CompactAction(
                            child: TextButton.icon(
                          onPressed: _busy || !StaffAccessService.can('cancel')
                              ? null
                              : _cancel,
                          icon: const Icon(Icons.cancel_outlined,
                              size: 16, color: Colors.red),
                          label: const Text('ยกเลิกออเดอร์',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        )),
                      ],
                    ),
                  ))),
            ),
          ],
        ));
  }
}

/// Small pill that mirrors the item's kitchen lifecycle on the cart row.
/// Show every state explicitly, including dishes not yet sent to the kitchen.
class _KitchenStatusChip extends StatelessWidget {
  const _KitchenStatusChip({required this.status});
  final KitchenStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      KitchenStatus.sent => ('ครัวรับแล้ว', Colors.amber.shade700),
      KitchenStatus.ready => ('พร้อมเสิร์ฟ', Colors.green),
      KitchenStatus.pending => ('รอส่งครัว', Colors.blueGrey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
