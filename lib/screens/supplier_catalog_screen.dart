import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/marketplace_order.dart';
import '../models/supplier.dart';
import '../services/marketplace_service.dart';

/// Browse a supplier's catalog and build a B2B order. Quantity steppers
/// per line; a sticky bottom bar shows the running total and submits the
/// order. Enforces the supplier's min-order before allowing submit.
class SupplierCatalogScreen extends StatefulWidget {
  const SupplierCatalogScreen({super.key, required this.supplier});
  final Supplier supplier;

  @override
  State<SupplierCatalogScreen> createState() =>
      _SupplierCatalogScreenState();
}

class _SupplierCatalogScreenState extends State<SupplierCatalogScreen> {
  static final _baht = NumberFormat('#,##0.00', 'th_TH');

  // productId → quantity
  final Map<String, int> _cart = {};
  // Snapshot of products so we can build order items without re-querying.
  final Map<String, SupplierProduct> _products = {};
  bool _placing = false;

  double get _total => _cart.entries.fold<double>(0, (s, e) {
        final p = _products[e.key];
        return s + (p == null ? 0 : p.price * e.value);
      });

  int get _itemCount => _cart.values.fold<int>(0, (s, q) => s + q);

  bool get _meetsMinimum => _total >= widget.supplier.minOrder;

  void _setQty(SupplierProduct p, int qty) {
    setState(() {
      _products[p.id] = p;
      if (qty <= 0) {
        _cart.remove(p.id);
      } else {
        _cart[p.id] = qty;
      }
    });
  }

  Future<void> _placeOrder() async {
    final items = _cart.entries.map((e) {
      final p = _products[e.key]!;
      return MarketplaceOrderItem(
        productId: p.id,
        name: p.name,
        unit: p.unit,
        price: p.price,
        quantity: e.value,
      );
    }).toList();

    setState(() => _placing = true);
    try {
      await MarketplaceService.placeOrder(
        supplier: widget.supplier,
        items: items,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ส่งออเดอร์ไป ${widget.supplier.name} แล้ว'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _placing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('สั่งไม่สำเร็จ: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        centerTitle: true,
      ),
      body: StreamBuilder<List<SupplierProduct>>(
        stream: MarketplaceService.watchCatalog(widget.supplier.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snap.data ?? const [];
          if (products.isEmpty) {
            return Center(
              child: Text('ยังไม่มีสินค้าในแคตตาล็อก',
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5))),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            itemCount: products.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: cs.outlineVariant),
            itemBuilder: (_, i) {
              final p = products[i];
              return _CatalogRow(
                product: p,
                quantity: _cart[p.id] ?? 0,
                onChanged: (q) => _setQty(p, q),
              );
            },
          );
        },
      ),
      bottomSheet: _cart.isEmpty
          ? null
          : _CartBar(
              total: _total,
              itemCount: _itemCount,
              minOrder: widget.supplier.minOrder,
              meetsMinimum: _meetsMinimum,
              placing: _placing,
              baht: _baht,
              onPlace: _placeOrder,
            ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.product,
    required this.quantity,
    required this.onChanged,
  });
  final SupplierProduct product;
  final int quantity;
  final void Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unavailable = !product.available;
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '฿${product.price.toStringAsFixed(0)} / ${product.unit}'
                    '${product.moq > 1 ? ' · ขั้นต่ำ ${product.moq}' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  if (unavailable)
                    Text('สินค้าหมด',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.error,
                            fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (!unavailable)
              quantity == 0
                  ? OutlinedButton(
                      onPressed: () => onChanged(product.moq),
                      child: const Text('เพิ่ม'),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            // Drop to 0 if going below MOQ, else step down.
                            final next = quantity - 1;
                            onChanged(next < product.moq ? 0 : next);
                          },
                        ),
                        Text('$quantity',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => onChanged(quantity + 1),
                        ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.total,
    required this.itemCount,
    required this.minOrder,
    required this.meetsMinimum,
    required this.placing,
    required this.baht,
    required this.onPlace,
  });

  final double total;
  final int itemCount;
  final double minOrder;
  final bool meetsMinimum;
  final bool placing;
  final NumberFormat baht;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!meetsMinimum)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'ยอดสั่งขั้นต่ำ ฿${minOrder.toStringAsFixed(0)} — '
                  'เพิ่มอีก ฿${(minOrder - total).toStringAsFixed(0)}',
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$itemCount รายการ',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                cs.onSurface.withValues(alpha: 0.6))),
                    Text('฿${baht.format(total)}',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cs.primary)),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        (placing || !meetsMinimum) ? null : onPlace,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: placing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('ส่งออเดอร์'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
