import 'package:flutter/material.dart';
import '../widgets/shop_operation.dart';
import '../utils/operation_error.dart';

import '../models/restaurant_table.dart';
import '../models/table_order.dart';
import '../models/sale.dart';
import '../services/settings_service.dart';
import '../services/table_service.dart';
import '../services/quantity_edit_queue.dart';
import '../widgets/modifier_picker_sheet.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/product_picker_sheet.dart';
import '../widgets/split_bill_sheet.dart';
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
      ),
      body: StreamBuilder<TableOrder?>(
        stream: TableService.watchOpenOrderForTable(table.id),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('โหลดออเดอร์ไม่สำเร็จ กรุณาเปิดหน้าโต๊ะใหม่'));
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
        setState(() => _opening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปิดออเดอร์ไม่สำเร็จ: $e')),
        );
      }
    }
    // On success, the StreamBuilder above rebuilds with the new order;
    // this widget gets disposed so no setState needed.
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
            const Text('โต๊ะนี้ว่าง',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'เปิดออเดอร์เพื่อเริ่มรับสินค้าจากลูกค้า',
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
      this.loadServiceCharge});
  final TableOrder order;
  final Future<void> Function(String, String, int, int)? changeQuantity;
  final Future<double> Function()? loadServiceCharge;

  @override
  State<TableOrderView> createState() => _OpenOrderViewState();
}

class _OpenOrderViewState extends State<TableOrderView> {
  bool _closing = false;
  bool _sending = false;
  final Map<String, int> _quantityPreview = {};
  final Map<String, QuantityEditQueue> _quantityQueues = {};
  @override
  void dispose() {
    for (final queue in _quantityQueues.values) {
      queue.dispose();
    }
    super.dispose();
  }

  bool get _busy => _closing || _sending || _quantityPreview.isNotEmpty;
  double get _subtotal => widget.order.items.fold(
      0.0,
      (sum, item) =>
          sum + item.unitPrice * (_quantityPreview[item.id] ?? item.quantity));
  double _serviceChargePercent = 0;

  @override
  void initState() {
    super.initState();
    (widget.loadServiceCharge ?? SettingsService.getServiceChargePercent)()
        .then((pct) {
      if (mounted) setState(() => _serviceChargePercent = pct);
    });
  }

  Future<void> _addItem() async {
    final picked = await showProductPicker(context);
    if (picked == null || !mounted) return;

    // Always open the picker: it collects modifier choices (if the product
    // has groups) plus an optional kitchen note for any dish.
    final pick = await showModifierPicker(context, product: picked);
    if (pick == null || !mounted) return; // user cancelled the sheet

    final item = TableService.itemFromProduct(
      picked,
      modifiers: pick.modifiers,
      notes: pick.notes,
    );
    if (!mounted) return;
    await performShopOperation(
        context, () => TableService.addItem(widget.order.id, item),
        success: 'เพิ่มรายการรอส่งครัวแล้ว');
  }

  Future<void> _changeQty(int index, int delta) async {
    final item = widget.order.items[index];
    if (!_closing && !_sending && item.kitchenStatus == KitchenStatus.pending) {
      final queue = _quantityQueues.putIfAbsent(item.id, () {
        late QuantityEditQueue value;
        value = QuantityEditQueue(
            quantity: item.quantity,
            save: (expected, target) =>
                widget.changeQuantity
                    ?.call(widget.order.id, item.id, target, expected) ??
                TableService.setItemQuantity(widget.order.id, item.id, target,
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
            widget.order.id, item.id, item.quantity + delta, item.quantity);
      } else {
        await TableService.setItemQuantity(
            widget.order.id, item.id, item.quantity + delta,
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

  double get _serviceCharge => _serviceChargePercent <= 0
      ? 0
      : _subtotal * (_serviceChargePercent / 100);
  double get _grandTotal => _subtotal + _serviceCharge;
  bool get _hasPendingItems =>
      widget.order.items.any((i) => i.kitchenStatus == KitchenStatus.pending);

  Future<void> _sendToKitchen() async {
    if (_busy) return;
    setState(() => _sending = true);
    try {
      await runShopOperation(
          context, () => TableService.sendToKitchen(widget.order.id),
          message: 'กำลังส่งออเดอร์เข้าครัว');
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
    if (widget.order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรายการในออเดอร์')),
      );
      return;
    }
    final confirmedOrder = widget.order;
    final confirmedServiceCharge = _serviceChargePercent;
    setState(() => _closing = true);
    final result = await showPaymentSheet(context,
        total: _grandTotal, initialChannel: SalesChannel.dineIn);
    if (result == null || !mounted) {
      if (mounted) setState(() => _closing = false);
      return;
    }
    try {
      final navigator = Navigator.of(context);
      final saleId = await runShopOperation(
          context,
          () => TableService.closeOrder(
                order: confirmedOrder,
                paid: result.paid,
                discount: 0,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(operationError(e))),
        );
      }
    }
  }

  Future<void> _split() async {
    if (widget.order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรายการในออเดอร์')),
      );
      return;
    }
    final n = await showSplitBillSheet(context, total: _grandTotal);
    if (n == null || !mounted) return;
    await _close(splitCount: n);
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
          () => TableService.cancelOrder(widget.order,
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
    final order = widget.order;
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
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(item.productName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              ),
                              _KitchenStatusChip(status: item.kitchenStatus),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                                onPressed: (_closing ||
                                        _sending ||
                                        (item.kitchenStatus !=
                                                KitchenStatus.pending &&
                                            _quantityPreview
                                                .containsKey(item.id)))
                                    ? null
                                    : () => _changeQty(i, -1),
                              ),
                              Text('${item.quantity}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: (_closing ||
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
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_quantityPreview.isNotEmpty)
                      const LinearProgressIndicator(),
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
                                  color: cs.onSurface.withValues(alpha: 0.6))),
                          Text('฿${_subtotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: 0.7))),
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
                                  color: cs.onSurface.withValues(alpha: 0.6))),
                          Text('฿${_serviceCharge.toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withValues(alpha: 0.7))),
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
                                color: cs.onSurface.withValues(alpha: 0.7))),
                        Text('฿${_grandTotal.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: cs.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _addItem,
                            icon: const Icon(Icons.add),
                            label: const Text('เพิ่มสินค้า'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_hasPendingItems)
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _busy ? null : _sendToKitchen,
                              icon: const Icon(Icons.soup_kitchen_outlined),
                              label: Text(
                                  'ส่งครัว (${widget.order.items.where((i) => i.kitchenStatus == KitchenStatus.pending).fold<int>(0, (sum, i) => sum + i.quantity)})'),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy || empty ? null : _split,
                            icon: const Icon(Icons.call_split),
                            label: const Text('แยกบิล'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _busy || empty ? null : () => _close(),
                            icon: _closing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.point_of_sale_outlined),
                            label: const Text('ปิดบิล'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: _busy ? null : _cancel,
                      icon: const Icon(Icons.cancel_outlined,
                          size: 16, color: Colors.red),
                      label: const Text('ยกเลิกออเดอร์',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
              ),
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
