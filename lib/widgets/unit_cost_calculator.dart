import 'package:flutter/material.dart';

double unitCost(
    {required double batchCost,
    required double yieldCount,
    required double packaging}) {
  if (!batchCost.isFinite ||
      !yieldCount.isFinite ||
      !packaging.isFinite ||
      batchCost < 0 ||
      yieldCount <= 0 ||
      packaging < 0) {
    throw ArgumentError('ต้นทุนต้องไม่ติดลบ และจำนวนที่ทำได้ต้องมากกว่าศูนย์');
  }
  return batchCost / yieldCount + packaging;
}

Future<double?> showUnitCostCalculator(BuildContext context) =>
    showDialog<double>(context: context, builder: (_) => const _Calculator());

class _Calculator extends StatefulWidget {
  const _Calculator();
  @override
  State<_Calculator> createState() => _CalculatorState();
}

class _CalculatorState extends State<_Calculator> {
  final _batch = TextEditingController();
  final _yield = TextEditingController();
  final _packaging = TextEditingController(text: '0');
  String? _error;
  @override
  void dispose() {
    _batch.dispose();
    _yield.dispose();
    _packaging.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('คำนวณต้นทุนต่อหน่วย'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'รวมค่าวัตถุดิบที่ใช้จริงต่อรอบ รวมของเสียในต้นทุน แล้วกรอกจำนวนที่ขายได้'),
          for (final field in [
            (_batch, 'ต้นทุนวัตถุดิบรวมต่อรอบ (บาท)'),
            (_yield, 'จำนวนที่ขายได้ต่อรอบ'),
            (_packaging, 'บรรจุภัณฑ์ต่อหน่วย (บาท)')
          ])
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                    controller: field.$1,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: field.$2))),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () {
                try {
                  final value = unitCost(
                      batchCost: double.parse(_batch.text),
                      yieldCount: double.parse(_yield.text),
                      packaging: double.parse(_packaging.text));
                  Navigator.pop(context, value);
                } catch (_) {
                  setState(() => _error =
                      'กรอกตัวเลขให้ครบ ต้นทุนไม่ติดลบ และจำนวนมากกว่าศูนย์');
                }
              },
              child: const Text('ใช้ต้นทุนนี้'))
        ],
      );
}
