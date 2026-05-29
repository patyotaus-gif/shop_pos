import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sale.dart';
import '../services/settings_service.dart';
import '../utils/promptpay_qr.dart';

/// Result returned by the payment sheet after the cashier confirms.
class PaymentResult {
  final PaymentMethod method;

  /// Cash received (cash method only) — used to compute change.
  /// For transfer/QR this equals the total.
  final double paid;

  /// Free-form reference (slip/transaction ID), optional, transfer only.
  final String? ref;

  const PaymentResult({
    required this.method,
    required this.paid,
    this.ref,
  });
}

/// In-cart payment flow shown as a draggable bottom sheet after the
/// cashier hits "ชำระเงิน" on the POS screen.
///
/// Why a sheet instead of inline chips:
///   - Method selection is irrelevant while the cashier is still
///     picking items, so it shouldn't take vertical real estate.
///   - The cash flow needs a number-pad anyway, so the dialog had to
///     pop up either way — folding "pick method" + "type amount" into
///     a single surface saves one tap and one screen transition.
class _PaymentSheet extends StatefulWidget {
  final double total;

  const _PaymentSheet({required this.total});

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  static const _prefsKey = 'pos_last_payment_method';
  static final _baht = NumberFormat('#,##0.00', 'th_TH');

  // PaymentMethod.online is intentionally excluded — that label belongs
  // to orders coming in from pok-pok.app/order; the cashier never picks
  // it manually for an in-store sale.
  static const _selectable = [
    PaymentMethod.cash,
    PaymentMethod.transfer,
    PaymentMethod.qr,
  ];

  PaymentMethod _method = PaymentMethod.cash;
  final _cashCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  // PromptPay payload + receiver — loaded lazily when QR is picked.
  String? _ppPayload;
  String? _ppReceiverName;
  bool _ppLoading = false;
  String? _ppError;

  @override
  void initState() {
    super.initState();
    _loadLastMethod();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLastMethod() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (!mounted || saved == null) return;
    final restored = _selectable.firstWhere(
      (m) => m.name == saved,
      orElse: () => PaymentMethod.cash,
    );
    if (restored != _method) {
      setState(() => _method = restored);
      if (restored == PaymentMethod.qr) {
        unawaited(_loadPromptPay());
      }
    }
  }

  Future<void> _persistMethod(PaymentMethod m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, m.name);
  }

  Future<void> _loadPromptPay() async {
    if (_ppPayload != null || _ppLoading) return;
    setState(() {
      _ppLoading = true;
      _ppError = null;
    });
    try {
      final pp = await SettingsService.getPromptPaySettings();
      final id = pp['promptpayId']?.trim() ?? '';
      if (id.isEmpty) {
        if (mounted) {
          setState(() {
            _ppLoading = false;
            _ppError =
                'ยังไม่ได้ตั้ง PromptPay ID — ไปที่ ตั้งค่า → รับเงินออนไลน์';
          });
        }
        return;
      }
      final payload = PromptPayQR.generate(id, amount: widget.total);
      if (!mounted) return;
      setState(() {
        _ppLoading = false;
        _ppPayload = payload;
        _ppReceiverName = pp['promptpayName'] ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ppLoading = false;
        _ppError = 'สร้าง QR ไม่สำเร็จ: $e';
      });
    }
  }

  void _selectMethod(PaymentMethod m) {
    if (m == _method) return;
    setState(() => _method = m);
    _persistMethod(m);
    if (m == PaymentMethod.qr) {
      unawaited(_loadPromptPay());
    }
  }

  double? get _cashReceived => double.tryParse(_cashCtrl.text.trim());

  double get _change {
    final received = _cashReceived ?? 0;
    return received - widget.total;
  }

  bool get _canConfirm {
    switch (_method) {
      case PaymentMethod.cash:
        final r = _cashReceived;
        return r != null && r >= widget.total;
      case PaymentMethod.qr:
        return _ppPayload != null;
      case PaymentMethod.transfer:
        return true; // ref is optional
      case PaymentMethod.online:
        return false;
    }
  }

  void _confirm() {
    final paid = _method == PaymentMethod.cash
        ? (_cashReceived ?? widget.total)
        : widget.total;
    Navigator.pop(
      context,
      PaymentResult(
        method: _method,
        paid: paid,
        ref: _method == PaymentMethod.transfer
            ? _refCtrl.text.trim().isEmpty
                ? null
                : _refCtrl.text.trim()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) {
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text('ยอดสุทธิ',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('฿${_baht.format(widget.total)}',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Text('วิธีชำระเงิน',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    )),
                const SizedBox(height: 8),
                Row(
                  children: _selectable
                      .map((m) => Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: m == _selectable.last ? 0 : 8),
                              child: _MethodButton(
                                method: m,
                                selected: _method == m,
                                onTap: () => _selectMethod(m),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                _buildMethodBody(cs),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _canConfirm ? _confirm : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: _canConfirm ? Colors.green : null,
                  ),
                  child: const Text('ยืนยันการชำระเงิน',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMethodBody(ColorScheme cs) {
    switch (_method) {
      case PaymentMethod.cash:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _cashCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                labelText: 'จำนวนเงินที่รับ',
                prefixText: '฿ ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            // Quick amount suggestions: total + a few common round-ups
            Wrap(
              spacing: 6,
              children: _suggestions().map((amt) {
                return ActionChip(
                  label: Text('฿${_baht.format(amt)}',
                      style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _cashCtrl.text = amt.toStringAsFixed(
                        amt == amt.roundToDouble() ? 0 : 2);
                    setState(() {});
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('เงินทอน',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                Text(
                  _change >= 0
                      ? '฿${_baht.format(_change)}'
                      : '(ขาด ฿${_baht.format(-_change)})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _change >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        );
      case PaymentMethod.qr:
        if (_ppLoading) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (_ppError != null) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_ppError!,
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
          );
        }
        if (_ppPayload == null) return const SizedBox.shrink();
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: _ppPayload!,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            if ((_ppReceiverName ?? '').isNotEmpty)
              Text('ผู้รับ: $_ppReceiverName',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            const Text('ให้ลูกค้าสแกน QR → กดยืนยันเมื่อโอนสำเร็จ',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        );
      case PaymentMethod.transfer:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: 'เลขอ้างอิง (ไม่บังคับ)',
                hintText: 'เช่น เลขสลิป 8 ตัวท้าย',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text('ตรวจในแอปธนาคารแล้วกดยืนยัน',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        );
      case PaymentMethod.online:
        return const SizedBox.shrink();
    }
  }

  /// Generate a few quick-pick amounts: exact, next 10, 20, 50, 100 multiples.
  List<double> _suggestions() {
    final t = widget.total;
    final set = <double>{t};
    for (final step in [10.0, 20.0, 50.0, 100.0, 500.0, 1000.0]) {
      if (step <= t) continue;
      final r = (t / step).ceil() * step;
      if (r > t) set.add(r.toDouble());
    }
    // Always offer the next full hundred above the total.
    final h = ((t / 100).ceil() * 100).toDouble();
    if (h > t) set.add(h);
    return set.toList()..sort();
  }
}

class _MethodButton extends StatelessWidget {
  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  const _MethodButton({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon => switch (method) {
        PaymentMethod.cash => Icons.payments_outlined,
        PaymentMethod.transfer => Icons.account_balance_outlined,
        PaymentMethod.qr => Icons.qr_code_2,
        PaymentMethod.online => Icons.public,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon,
                size: 26,
                color: selected
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.7)),
            const SizedBox(height: 4),
            Text(method.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? cs.onPrimaryContainer
                      : cs.onSurface.withValues(alpha: 0.85),
                )),
          ],
        ),
      ),
    );
  }
}

/// Show the payment sheet and await the cashier's choice.
/// Returns null if they cancel.
Future<PaymentResult?> showPaymentSheet(
  BuildContext context, {
  required double total,
}) {
  return showModalBottomSheet<PaymentResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _PaymentSheet(total: total),
  );
}

// Local stand-in for `unawaited` so we don't need to import dart:async
// in this file.
void unawaited(Future<void> _) {}
