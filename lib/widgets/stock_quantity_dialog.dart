import 'package:flutter/material.dart';
import '../utils/stock_quantity.dart';

Future<num?> showStockQuantity(BuildContext context,
        {required String unit, bool weighed = false, num initial = 1}) =>
    showDialog<num>(
        context: context,
        builder: (_) => StockQuantityDialog(
            unit: unit, weighed: weighed, initial: initial));

class StockQuantityDialog extends StatefulWidget {
  const StockQuantityDialog(
      {super.key,
      required this.unit,
      required this.weighed,
      required this.initial});
  final String unit;
  final bool weighed;
  final num initial;
  @override
  State<StockQuantityDialog> createState() => _StockQuantityDialogState();
}

class _StockQuantityDialogState extends State<StockQuantityDialog> {
  late final controller =
      TextEditingController(text: stockText(widget.initial));
  String? error;
  void submit() {
    final q = num.tryParse(controller.text.trim());
    if (q == null || !validStockQuantity(q, weight: widget.weighed) || q > 99) {
      setState(() => error = widget.weighed
          ? 'ระบุจำนวนมากกว่า 0 ถึง 99 ทศนิยมไม่เกิน 3 ตำแหน่ง'
          : 'ระบุจำนวนเต็ม 1–99');
      return;
    }
    Navigator.pop(context, q);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('จำนวน (${widget.unit})'),
          content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  TextInputType.numberWithOptions(decimal: widget.weighed),
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                  errorText: error,
                  helperText: widget.weighed
                      ? 'ราคาคิดต่อ ${widget.unit} · เช่น 0.250'
                      : null)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก')),
            FilledButton(onPressed: submit, child: const Text('ตกลง'))
          ]);
}
