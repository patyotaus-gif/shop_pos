import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../utils/receipt_generator.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _baht = NumberFormat('#,##0.00', 'th_TH');
  final List<CartItem> _cart = [];
  double _discount = 0;
  bool _scanning = false;
  PaymentMethod _paymentMethod = PaymentMethod.cash;

  double get _subtotal => _cart.fold(0, (s, e) => s + e.subtotal);
  double get _total => _subtotal - _discount;

  void _addToCart(Product product) {
    setState(() {
      final idx = _cart.indexWhere((e) => e.product.id == product.id);
      if (idx >= 0) {
        _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity + 1);
      } else {
        _cart.add(CartItem(product: product));
      }
    });
  }

  void _removeFromCart(int idx) => setState(() => _cart.removeAt(idx));

  void _updateQty(int idx, int qty) {
    if (qty <= 0) {
      _removeFromCart(idx);
    } else {
      setState(() => _cart[idx] = _cart[idx].copyWith(quantity: qty));
    }
  }

  Future<void> _onBarcodeDetected(String barcode) async {
    setState(() => _scanning = false);
    final product = await ProductService.getByBarcode(barcode);
    if (!mounted) return;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่พบสินค้า barcode: $barcode'),
          action: SnackBarAction(
            label: 'เพิ่มสินค้า',
            onPressed: () => Navigator.pushNamed(context, '/product-form',
                arguments: barcode),
          ),
        ),
      );
    } else {
      _addToCart(product);
    }
  }

  Future<void> _checkout({bool isDebt = false}) async {
    if (_cart.isEmpty) return;

    String? customerName;
    if (isDebt) {
      customerName = await _askCustomerName();
      if (customerName == null) return;
    }

    double paid = 0.0;
    if (!isDebt) {
      if (_paymentMethod == PaymentMethod.cash) {
        paid = await _askPayment();
        if (paid < 0) return;
      } else {
        paid = _total;
      }
    }

    try {
      final sale = await SaleService.checkout(
        cart: _cart,
        paid: paid,
        discount: _discount,
        isDebt: isDebt,
        customerName: customerName,
        paymentMethod: _paymentMethod,
      );

      setState(() {
        _cart.clear();
        _discount = 0;
      });

      if (mounted) {
        _showReceiptDialog(sale);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  Future<double> _askPayment() async {
    final ctrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('รับเงิน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ยอดรวม: ฿${_baht.format(_total)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'จำนวนเงินที่รับ',
                prefixText: '฿',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, -1.0), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text) ?? -1;
              if (v < _total) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('จำนวนเงินไม่พอ')),
                );
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    return result ?? -1;
  }

  Future<String?> _askCustomerName() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ชื่อลูกค้า (เชื่อ)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ชื่อลูกค้า',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }

  void _showReceiptDialog(Sale sale) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ขายสำเร็จ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 8),
            Text('ยอดรวม ฿${_baht.format(sale.total)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (!sale.isDebt)
              Text('เงินทอน ฿${_baht.format(sale.change)}',
                  style: const TextStyle(fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด')),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await ReceiptGenerator.printReceipt(sale);
            },
            icon: const Icon(Icons.receipt_long),
            label: const Text('พิมพ์ใบเสร็จ'),
          ),
        ],
      ),
    );
  }

  Future<void> _setDiscount() async {
    final ctrl = TextEditingController(text: _discount > 0 ? _discount.toString() : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ส่วนลด'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ส่วนลด (บาท)',
            prefixText: '฿',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('ล้างส่วนลด')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _discount = result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => setState(() => _scanning = true),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning)
            SizedBox(
              height: 200,
              child: MobileScanner(
                onDetect: (capture) {
                  final barcode = capture.barcodes.firstOrNull?.rawValue;
                  if (barcode != null && _scanning) _onBarcodeDetected(barcode);
                },
              ),
            ),
          // Product search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _ProductSearch(onSelected: _addToCart),
          ),
          // Pinned products
          StreamBuilder<List<Product>>(
            stream: ProductService.watchAll(),
            builder: (ctx, snap) {
              final pinned = (snap.data ?? []).where((p) => p.isPinned).toList();
              if (pinned.isEmpty) return const SizedBox.shrink();
              return SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pinned.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(pinned[i].name, style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.push_pin, size: 14),
                      onPressed: () => _addToCart(pinned[i]),
                    ),
                  ),
                ),
              );
            },
          ),
          // Payment method selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: PaymentMethod.values.map((m) {
                final selected = _paymentMethod == m;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(m.label, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) => setState(() => _paymentMethod = m),
                  ),
                );
              }).toList(),
            ),
          ),
          // Cart
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shopping_cart_outlined,
                            size: 64, color: cs.onSurface.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        Text('ยังไม่มีสินค้าในตะกร้า',
                            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4))),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _cart.length,
                    itemBuilder: (ctx, i) => _CartItemTile(
                      item: _cart[i],
                      onRemove: () => _removeFromCart(i),
                      onQtyChanged: (qty) => _updateQty(i, qty),
                    ),
                  ),
          ),
          // Summary & checkout
          _CheckoutPanel(
            subtotal: _subtotal,
            discount: _discount,
            total: _total,
            onDiscount: _setDiscount,
            onCheckout: () => _checkout(),
            onDebt: () => _checkout(isDebt: true),
            hasItems: _cart.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

// --- Sub-widgets ---

class _ProductSearch extends StatefulWidget {
  final ValueChanged<Product> onSelected;
  const _ProductSearch({required this.onSelected});

  @override
  State<_ProductSearch> createState() => _ProductSearchState();
}

class _ProductSearchState extends State<_ProductSearch> {
  final _ctrl = TextEditingController();
  List<Product> _results = [];

  void _search(String q) {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    ProductService.watchAll().first.then((products) {
      setState(() {
        _results = products
            .where((p) =>
                p.name.toLowerCase().contains(q.toLowerCase()) ||
                p.barcode.contains(q))
            .take(5)
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _ctrl,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: 'ค้นหาสินค้า...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      _search('');
                    },
                  )
                : null,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (_results.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: _results
                  .map((p) => ListTile(
                        dense: true,
                        title: Text(p.name),
                        subtitle: Text('฿${p.price.toStringAsFixed(2)} · สต็อก ${p.stock}'),
                        trailing: Text(p.barcode,
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        onTap: () {
                          widget.onSelected(p);
                          _ctrl.clear();
                          _search('');
                        },
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChanged;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final baht = NumberFormat('#,##0.00', 'th_TH');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('฿${baht.format(item.product.price)} × ${item.quantity}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('฿${baht.format(item.subtotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => onQtyChanged(item.quantity - 1),
            ),
            Text('${item.quantity}'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onQtyChanged(item.quantity + 1),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutPanel extends StatelessWidget {
  final double subtotal, discount, total;
  final VoidCallback onDiscount, onCheckout, onDebt;
  final bool hasItems;

  const _CheckoutPanel({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.onDiscount,
    required this.onCheckout,
    required this.onDebt,
    required this.hasItems,
  });

  @override
  Widget build(BuildContext context) {
    final baht = NumberFormat('#,##0.00', 'th_TH');
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('รวม'),
              Text('฿${baht.format(subtotal)}'),
            ],
          ),
          if (discount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ส่วนลด', style: TextStyle(color: Colors.green)),
                Text('-฿${baht.format(discount)}',
                    style: const TextStyle(color: Colors.green)),
              ],
            ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ยอดสุทธิ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('฿${baht.format(total)}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onDiscount,
                icon: const Icon(Icons.discount_outlined),
                label: const Text('ส่วนลด'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasItems ? onDebt : null,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('เชื่อ'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: hasItems ? onCheckout : null,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('ชำระเงิน'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
