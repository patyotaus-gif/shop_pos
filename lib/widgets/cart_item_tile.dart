import 'package:flutter/material.dart';
import '../utils/money_format.dart';
import '../models/cart_item.dart';
import 'product_image.dart';

class CartItemTile extends StatelessWidget {
  const CartItemTile(
      {super.key,
      required this.item,
      required this.onRemove,
      required this.onQtyChanged});
  final CartItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final detailStyle = TextStyle(fontSize: 14, color: cs.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
              builder: (context, constraints) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (constraints.maxWidth >= 360 &&
                                  (item.product.imagePath != null ||
                                      (item.product.imageUrl ?? '')
                                          .isNotEmpty)) ...[
                                ProductImage(
                                    product: item.product,
                                    width: 44,
                                    height: 44,
                                    borderRadius: BorderRadius.circular(6)),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(item.product.name,
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'หน่วยละ ${formatBaht(item.unitPrice)}',
                                        style: detailStyle),
                                    if (item.modifiers.isNotEmpty)
                                      Text(
                                          item.modifiers
                                              .map((m) => m.optionName)
                                              .join(', '),
                                          style: detailStyle),
                                    if (item.notes?.isNotEmpty ?? false)
                                      Text('หมายเหตุ: ${item.notes!}',
                                          style: detailStyle),
                                  ])),
                            ]),
                        const SizedBox(height: 8),
                        Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(formatBaht(item.subtotal),
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    IconButton(
                                        tooltip: 'ลดจำนวน',
                                        onPressed: () =>
                                            onQtyChanged(item.quantity - 1),
                                        icon: const Icon(
                                            Icons.remove_circle_outline)),
                                    TextButton(
                                        onPressed: () async {
                                          final quantity =
                                              await showDialog<int>(
                                                  context: context,
                                                  builder: (_) =>
                                                      _QuantityDialog(
                                                          quantity:
                                                              item.quantity));
                                          if (quantity != null &&
                                              context.mounted) {
                                            onQtyChanged(quantity);
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                            minimumSize: const Size(48, 48)),
                                        child: Text('${item.quantity}',
                                            semanticsLabel:
                                                'จำนวน ${item.quantity} แตะเพื่อแก้ไข')),
                                    IconButton(
                                        tooltip: 'เพิ่มจำนวน',
                                        onPressed: () =>
                                            onQtyChanged(item.quantity + 1),
                                        icon: const Icon(
                                            Icons.add_circle_outline)),
                                    IconButton(
                                        tooltip: 'ลบรายการ',
                                        onPressed: onRemove,
                                        icon: Icon(Icons.delete_outline,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)),
                                  ]),
                            ]),
                      ]))),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.quantity});
  final int quantity;
  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: '${widget.quantity}');
  String? _error;
  void _submit() {
    final quantity = int.tryParse(_controller.text.trim());
    if (quantity == null || quantity < 1) {
      setState(() => _error = 'กรอกจำนวนเต็มตั้งแต่ 1 ขึ้นไป');
      return;
    }
    Navigator.pop(context, quantity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('จำนวน'),
        content: TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
                border: const OutlineInputBorder(), errorText: _error)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(onPressed: _submit, child: const Text('ตกลง')),
        ],
      );
}
