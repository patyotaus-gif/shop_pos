import 'package:flutter/material.dart';

Future<double?> showSupplierQuantity(
        BuildContext context, double quantity, double minimum, String unit) =>
    showDialog<double>(
        context: context,
        builder: (_) =>
            _Quantity(quantity: quantity, minimum: minimum, unit: unit));

class _Quantity extends StatefulWidget {
  const _Quantity(
      {required this.quantity, required this.minimum, required this.unit});
  final double quantity, minimum;
  final String unit;
  @override
  State<_Quantity> createState() => _QuantityState();
}

class _QuantityState extends State<_Quantity> {
  late final _controller = TextEditingController(text: '${widget.quantity}');
  String? _error;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('จำนวน (${widget.unit})'),
        content: TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                helperText: 'ขั้นต่ำ ${widget.minimum} หรือ 0 เพื่อลบ',
                errorText: _error)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () {
                final value = double.tryParse(_controller.text);
                if (value == null ||
                    !value.isFinite ||
                    value < 0 ||
                    (value > 0 && value < widget.minimum)) {
                  setState(() => _error = 'จำนวนไม่ถูกต้องหรือน้อยกว่าขั้นต่ำ');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('ตกลง'))
        ],
      );
}
