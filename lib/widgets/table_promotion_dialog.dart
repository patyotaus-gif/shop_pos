import 'package:flutter/material.dart';
import '../utils/operation_error.dart';

class TablePromotionDialog extends StatefulWidget {
  const TablePromotionDialog(
      {super.key,
      required this.load,
      required this.apply,
      this.initialCode = ''});
  final Future<Map<String, dynamic>> Function(String code) load;
  final Future<void> Function(String code, String revision) apply;
  final String initialCode;
  @override
  State<TablePromotionDialog> createState() => _TablePromotionDialogState();
}

class _TablePromotionDialogState extends State<TablePromotionDialog> {
  late final TextEditingController _code;
  Map<String, dynamic>? _quote;
  String? _error;
  bool _busy = false;
  String _checkedCode = '';
  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: widget.initialCode);
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get code => _code.text.trim().toUpperCase();
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _quote = null;
      _error = null;
    });
    final requested = code;
    try {
      final quote = await widget.load(requested);
      if (mounted) {
        setState(() {
          _quote = quote;
          _checkedCode = requested;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_quote == null || code != _checkedCode || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.apply(code, _quote!['revision'] as String);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = operationError(e);
          _quote = null;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String money(dynamic minor) =>
      '฿${((minor as num) / 100).toStringAsFixed(2)}';
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: const Text('โปรโมชั่นบิลโต๊ะ'),
          content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                      controller: _code,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                          labelText: 'โค้ดส่วนลด (ถ้ามี)'),
                      onChanged: (_) => setState(() => _quote = null)),
                  const SizedBox(height: 8),
                  const Text(
                      'ตรวจจากสินค้าทั้งโต๊ะ คูปองใช้สิทธิ์เมื่อปิดบิลสำเร็จ'),
                  TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('ตรวจโปรโมชั่น')),
                  if (code.isNotEmpty)
                    TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                _code.clear();
                                _load();
                              },
                        child: const Text('นำคูปองออก')),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_quote case final q?) ...[
                    Text('ค่าสินค้า ${money(q['subtotalMinor'])}'),
                    for (final b in q['bundles'] as List)
                      Text(
                          '${b['name']} × ${b['sets']} ลด ${money(b['discountMinor'])}'),
                    for (final g in q['buyGet'] as List)
                      Text('ของแถม: ${g['productName']} × ${g['quantity']}'),
                    if (q['coupon'] != null)
                      Text(
                          'คูปอง ${q['coupon']['code']} ลด ${money(q['coupon']['discountMinor'])}'),
                    if ((q['serviceMinor'] as num) > 0)
                      Text('ค่าบริการ ${money(q['serviceMinor'])}'),
                    const SizedBox(height: 8),
                    Text('ยอดชำระ ${money(q['totalMinor'])}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    if ((q['buyGet'] as List).isNotEmpty)
                      const Text(
                          'หลังยืนยัน ให้ส่งรายการของแถมเข้าครัวก่อนปิดบิล'),
                  ],
                ],
              ))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('กลับ')),
            FilledButton(
                onPressed: _busy || _quote == null ? null : _apply,
                child: const Text('ยืนยันยอดและของแถม')),
          ],
        ),
      );
}
