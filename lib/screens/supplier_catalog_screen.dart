import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/marketplace_order.dart';
import '../models/supplier.dart';
import '../services/marketplace_service.dart';

/// Browse a supplier's catalog and build a B2B order. Quantity steppers
/// per line; a sticky bottom bar shows the running total and submits the
/// order. Enforces the supplier's min-order before allowing submit.
class SupplierCatalogScreen extends StatefulWidget {
  const SupplierCatalogScreen({
    super.key,
    required this.supplier,
    this.initialItems,
  });
  final Supplier supplier;

  /// When opened via "สั่งซ้ำ", the items from a past order. The cart is
  /// pre-filled from these once the live catalog loads — reconciled against
  /// current availability and price (see [_reconcile]).
  final List<MarketplaceOrderItem>? initialItems;

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

  // "สั่งซ้ำ" reconciliation runs once, after the catalog first loads.
  bool _reconciled = false;

  // Favorited productIds (live) + productIds ordered before (fetched once).
  // Drive the "⭐ รายการโปรด" and "🕘 เคยสั่ง" sections at the top.
  Set<String> _favIds = {};
  Set<String> _orderedIds = {};
  StreamSubscription<Set<String>>? _favSub;

  @override
  void initState() {
    super.initState();
    _favSub = MarketplaceService.watchFavoriteIds(widget.supplier.id)
        .listen((ids) {
      if (mounted) setState(() => _favIds = ids);
    });
    MarketplaceService.previouslyOrderedProductIds(widget.supplier.id)
        .then((ids) {
      if (mounted) setState(() => _orderedIds = ids);
    });
  }

  @override
  void dispose() {
    _favSub?.cancel();
    super.dispose();
  }

  Future<void> _toggleFavorite(SupplierProduct p) async {
    final makeFav = !_favIds.contains(p.id);
    // Optimistic flip so the star responds instantly.
    setState(() => makeFav ? _favIds.add(p.id) : _favIds.remove(p.id));
    try {
      await MarketplaceService.toggleFavorite(
        supplierId: widget.supplier.id,
        product: p,
        makeFavorite: makeFav,
      );
    } catch (_) {
      if (mounted) {
        setState(() => makeFav ? _favIds.remove(p.id) : _favIds.add(p.id));
      }
    }
  }

  /// Rebuild the cart from [SupplierCatalogScreen.initialItems] against the
  /// live catalog: keep items that still exist and are in stock (at current
  /// price + clamped to current MOQ), and tell the shop which ones dropped
  /// off so they don't silently lose part of their usual order.
  void _reconcile(List<SupplierProduct> products) {
    final byId = {for (final p in products) p.id: p};
    final dropped = <String>[];
    setState(() {
      for (final it in widget.initialItems!) {
        final p = byId[it.productId];
        if (p == null || !p.available) {
          dropped.add(it.name);
          continue;
        }
        _products[p.id] = p;
        _cart[p.id] = it.quantity < p.moq ? p.moq : it.quantity;
      }
    });
    if (dropped.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('ไม่มีแล้ว ${dropped.length} รายการ: '
            '${dropped.join(", ")}'),
        duration: const Duration(seconds: 5),
      ));
    }
  }

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

  /// Group the catalog into favorites → previously-ordered → everything
  /// else, each under its own header. Sections only appear when non-empty,
  /// so a shop with no history just sees the full list.
  Widget _buildGroupedList(List<SupplierProduct> products, ColorScheme cs) {
    final favs = <SupplierProduct>[];
    final ordered = <SupplierProduct>[];
    final rest = <SupplierProduct>[];
    for (final p in products) {
      if (_favIds.contains(p.id)) {
        favs.add(p);
      } else if (_orderedIds.contains(p.id)) {
        ordered.add(p);
      } else {
        rest.add(p);
      }
    }

    final children = <Widget>[];
    void addSection(String? title, List<SupplierProduct> items) {
      if (items.isEmpty) return;
      if (title != null) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.primary)),
        ));
      }
      for (final p in items) {
        children.add(_CatalogRow(
          product: p,
          quantity: _cart[p.id] ?? 0,
          isFavorite: _favIds.contains(p.id),
          onChanged: (q) => _setQty(p, q),
          onToggleFavorite: () => _toggleFavorite(p),
        ));
      }
    }

    // Only label sections once there's more than one; a single flat list
    // doesn't need a "สินค้าทั้งหมด" header.
    final grouped = favs.isNotEmpty || ordered.isNotEmpty;
    addSection(grouped ? '⭐ รายการโปรด' : null, favs);
    addSection(grouped ? '🕘 เคยสั่ง' : null, ordered);
    addSection(grouped ? 'สินค้าทั้งหมด' : null, rest);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
      children: children,
    );
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
          // One-shot reorder reconciliation once the catalog is in hand.
          if (!_reconciled && widget.initialItems != null) {
            _reconciled = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _reconcile(products));
          }
          if (products.isEmpty) {
            return Center(
              child: Text('ยังไม่มีสินค้าในแคตตาล็อก',
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.5))),
            );
          }
          return _buildGroupedList(products, cs);
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
    required this.isFavorite,
    required this.onToggleFavorite,
  });
  final SupplierProduct product;
  final int quantity;
  final void Function(int) onChanged;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

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
            _Thumb(url: product.imageUrl),
            const SizedBox(width: 12),
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
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite
                    ? const Color(0xFFE0A500)
                    : cs.onSurface.withValues(alpha: 0.35),
                size: 22,
              ),
              tooltip: isFavorite ? 'เอาออกจากรายการโปรด' : 'เพิ่มรายการโปรด',
              onPressed: onToggleFavorite,
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

/// Square product thumbnail with a graceful fallback to a box icon when
/// the supplier hasn't uploaded a photo (or it fails to load).
class _Thumb extends StatelessWidget {
  const _Thumb({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.inventory_2_outlined,
          size: 24, color: cs.onSurface.withValues(alpha: 0.4)),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url!,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder,
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
