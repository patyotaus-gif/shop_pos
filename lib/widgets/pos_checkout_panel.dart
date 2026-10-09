import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'compact_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Presentation only; checkout and permission checks remain in the POS flow.
class PosCheckoutPanel extends StatefulWidget {
  const PosCheckoutPanel(
      {super.key,
      required this.subtotal,
      required this.discount,
      required this.total,
      required this.onDiscount,
      required this.onCheckout,
      required this.onDebt,
      required this.hasItems,
      required this.canDiscount,
      required this.canDebt,
      this.compact = false,
      this.preferenceKey});

  final double subtotal, discount, total;
  final VoidCallback onDiscount, onCheckout, onDebt;
  final bool hasItems, canDiscount, canDebt, compact;
  final String? preferenceKey;

  @override
  State<PosCheckoutPanel> createState() => _PosCheckoutPanelState();
}

class _PosCheckoutPanelState extends State<PosCheckoutPanel> {
  String? _pin;
  int _revision = 0;
  Future<void> _saving = Future.value();
  double get subtotal => widget.subtotal;
  double get discount => widget.discount;
  double get total => widget.total;
  bool get hasItems => widget.hasItems;
  bool get canDiscount => widget.canDiscount;
  bool get canDebt => widget.canDebt;
  bool get compact => widget.compact;
  VoidCallback get onDiscount => widget.onDiscount;
  VoidCallback get onDebt => widget.onDebt;
  VoidCallback get onCheckout => widget.onCheckout;
  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  @override
  void didUpdateWidget(covariant PosCheckoutPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.preferenceKey != oldWidget.preferenceKey) {
      _revision++;
      _pin = null;
      _loadPin();
    }
  }

  Future<void> _loadPin() async {
    final key = widget.preferenceKey;
    if (key == null) return;
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && revision == _revision) {
        setState(() => _pin = prefs.getString(key));
      }
    } catch (_) {/* Shortcut preferences must never block a sale. */}
  }

  void _setPin(String value) {
    setState(() {
      _revision++;
      _pin = value;
    });
    final key = widget.preferenceKey;
    if (key == null) return;
    _saving = _saving.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final baht = NumberFormat('#,##0.00', 'th_TH');
    final cs = Theme.of(context).colorScheme;
    final pinned =
        _pin == 'discount' && canDiscount || _pin == 'debt' && canDebt;
    final totalLabel = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinned)
            OutlinedButton(
                onPressed: _pin == 'discount'
                    ? onDiscount
                    : hasItems
                        ? onDebt
                        : null,
                child: Text(_pin == 'discount' ? 'ส่วนลด' : 'ขายเชื่อ')),
          Text('ยอดสุทธิ',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          Text('฿${baht.format(total)}',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ]);
    final actions = Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (canDiscount || canDebt)
            PopupMenuButton<String>(
              key: const ValueKey('checkout-more'),
              tooltip: 'ส่วนลด ขายเชื่อ และปักหมุดปุ่ม',
              icon: const Icon(Icons.more_vert),
              constraints: const BoxConstraints(minWidth: 180),
              onSelected: (value) {
                if (value == 'discount' && canDiscount) onDiscount();
                if (value == 'debt' && canDebt && hasItems) onDebt();
                if (value.startsWith('pin:')) _setPin(value.substring(4));
              },
              itemBuilder: (_) => [
                if (canDiscount)
                  const PopupMenuItem(value: 'discount', child: Text('ส่วนลด')),
                if (canDebt)
                  PopupMenuItem(
                      value: 'debt',
                      enabled: hasItems,
                      child: const Text('ขายเชื่อ')),
                const PopupMenuDivider(),
                if (canDiscount)
                  const PopupMenuItem(
                      value: 'pin:discount', child: Text('ปักหมุดปุ่มส่วนลด')),
                if (canDebt)
                  const PopupMenuItem(
                      value: 'pin:debt', child: Text('ปักหมุดปุ่มขายเชื่อ')),
                if (pinned)
                  const PopupMenuItem(
                      value: 'pin:none', child: Text('เอาปุ่มที่ปักหมุดออก')),
              ],
            ),
          FilledButton(
            key: const ValueKey('checkout-pay'),
            onPressed: hasItems ? onCheckout : null,
            style: FilledButton.styleFrom(
                minimumSize: const Size(112, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            child: const Text('ชำระเงิน'),
          ),
        ]);
    return SafeArea(
        top: false,
        child: Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: compact
              ? LayoutBuilder(builder: (context, constraints) {
                  // Retain readable text instead of squeezing large accessibility text
                  // or unusually large totals beside the payment controls.
                  final twoRows = pinned ||
                      constraints.maxWidth < 320 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18 ||
                      total.abs() >= 1000000;
                  return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (twoRows) ...[
                          totalLabel,
                          const SizedBox(height: 4),
                          Align(
                              alignment: Alignment.centerRight, child: actions),
                        ] else
                          Row(children: [
                            Expanded(child: totalLabel),
                            const SizedBox(width: 8),
                            actions
                          ]),
                        if (discount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                              'รวม ฿${baht.format(subtotal)} · ส่วนลด ฿${baht.format(discount)}',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ]);
                })
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  _amount('รวม', '฿${baht.format(subtotal)}'),
                  if (discount > 0)
                    _amount('ส่วนลด', '-฿${baht.format(discount)}'),
                  const Divider(),
                  Row(children: [
                    const Expanded(
                        child: Text('ยอดสุทธิ',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold))),
                    Flexible(
                        child: Text('฿${baht.format(total)}',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: cs.primary))),
                  ]),
                  const SizedBox(height: 12),
                  ActionButtons(children: [
                    OutlinedButton.icon(
                        onPressed: canDiscount ? onDiscount : null,
                        icon: const Icon(Icons.discount_outlined, size: 18),
                        label: const Text('ส่วนลด')),
                    OutlinedButton.icon(
                        onPressed: canDebt && hasItems ? onDebt : null,
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: const Text('เชื่อ')),
                    FilledButton.icon(
                        onPressed: hasItems ? onCheckout : null,
                        icon: const Icon(Icons.payments_outlined, size: 18),
                        label: const Text('ชำระเงิน')),
                  ]),
                ]),
        ));
  }

  Widget _amount(String label, String value) => Row(children: [
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ]);
}
