import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import 'product_image.dart';
import 'sale_product_grid.dart';

enum ProductCatalogLayout { list, grid }

/// Product management uses the same compact photo cards as the sales catalog.
/// Changing presentation must never edit products or reset the active filters.
class ProductCatalog extends StatefulWidget {
  const ProductCatalog(
      {super.key,
      required this.products,
      required this.categories,
      required this.preferenceKey,
      required this.onEdit,
      this.onReceiveStock,
      this.showInventory = false,
      this.loading = false,
      this.hasError = false});

  final List<Product> products;
  final List<String> categories;
  final String preferenceKey;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product>? onReceiveStock;
  final bool showInventory;
  final bool loading;
  final bool hasError;

  @override
  State<ProductCatalog> createState() => _ProductCatalogState();
}

class _ProductCatalogState extends State<ProductCatalog> {
  ProductCatalogLayout _layout = ProductCatalogLayout.list;
  final _search = TextEditingController();
  String _category = 'ทั้งหมด';
  int _revision = 0;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void didUpdateWidget(ProductCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferenceKey != widget.preferenceKey) {
      _revision++;
      _layout = ProductCatalogLayout.list;
      _search.clear();
      _category = 'ทั้งหมด';
      _loadLayout();
    }
  }

  Future<void> _loadLayout() async {
    final revision = _revision, key = widget.preferenceKey;
    try {
      await _pendingSave;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || revision != _revision || key != widget.preferenceKey) {
        return;
      }
      setState(() => _layout = prefs.getString(key) == 'grid'
          ? ProductCatalogLayout.grid
          : ProductCatalogLayout.list);
    } catch (_) {
      // A preference read must not prevent managing products.
    }
  }

  void _selectLayout(Set<ProductCatalogLayout> selection) {
    final layout = selection.single;
    final key = widget.preferenceKey;
    _revision++;
    setState(() => _layout = layout);
    // Serialize rapid taps so the last visible choice is also the saved choice.
    _pendingSave = _pendingSave.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(key, layout.name)) throw StateError('save');
      } catch (_) {
        if (mounted && widget.preferenceKey == key) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('เปลี่ยนมุมมองแล้ว แต่จำรูปแบบไม่สำเร็จ')));
        }
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _search.text.trim().toLowerCase();
    final products = widget.products
        .where((p) =>
            (search.isEmpty ||
                p.name.toLowerCase().contains(search) ||
                p.barcode.toLowerCase().contains(search)) &&
            (_category == 'ทั้งหมด' || p.category == _category))
        .toList();
    final scale = MediaQuery.textScalerOf(context);
    final footerHeight = math.max(48.0, scale.scale(14) + 16);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                hintText: 'ค้นหาสินค้า...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true),
          )),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: SegmentedButton<ProductCatalogLayout>(
            segments: const [
              ButtonSegment(
                  value: ProductCatalogLayout.list,
                  icon: Icon(Icons.view_list_outlined),
                  label: Text('รายการ'),
                  tooltip: 'แสดงสินค้าแบบรายการ'),
              ButtonSegment(
                  value: ProductCatalogLayout.grid,
                  icon: Icon(Icons.grid_view_outlined),
                  label: Text('รูปภาพ'),
                  tooltip: 'แสดงสินค้าแบบการ์ดรูปภาพ'),
            ],
            selected: {_layout},
            showSelectedIcon: false,
            onSelectionChanged: _selectLayout,
          ),
        ),
      ),
      SizedBox(
          height: math.max(48, scale.scale(16) + 24),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: ['ทั้งหมด', ...widget.categories]
                .map((cat) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat),
                        selected: cat == _category,
                        onSelected: (_) => setState(() => _category = cat),
                      ),
                    ))
                .toList(),
          )),
      Expanded(
          child: widget.hasError
              ? const Center(child: Text('โหลดสินค้าไม่สำเร็จ กรุณาลองใหม่'))
              : widget.loading
                  ? const Center(child: CircularProgressIndicator())
                  : products.isEmpty
                      ? const Center(child: Text('ไม่พบสินค้า'))
                      : _layout == ProductCatalogLayout.grid
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 80),
                              child: SaleProductGrid(
                                key: const PageStorageKey('products-grid'),
                                footerExtent: footerHeight,
                                itemCount: products.length,
                                itemBuilder: (context, i) {
                                  final product = products[i];
                                  return SaleProductCard(
                                    product: product,
                                    onTap: () => widget.onEdit(product),
                                    footer: SizedBox(
                                        height: footerHeight,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                              left: 10, right: 4),
                                          child: Row(children: [
                                            Expanded(
                                                child: Text(
                                                    'สต็อก ${product.stock}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 14,
                                                        color: widget
                                                                    .showInventory &&
                                                                product
                                                                    .isLowStock
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .error
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant))),
                                            if (widget.showInventory &&
                                                widget.onReceiveStock != null)
                                              IconButton(
                                                  tooltip: 'รับสินค้าเข้า',
                                                  icon: const Icon(
                                                      Icons.add_box_outlined),
                                                  onPressed: () =>
                                                      widget.onReceiveStock!(
                                                          product)),
                                          ]),
                                        )),
                                  );
                                },
                              ))
                          : ListView.builder(
                              key: const PageStorageKey('products-list'),
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                              itemCount: products.length,
                              itemBuilder: (context, i) => _ProductListRow(
                                product: products[i],
                                showInventory: widget.showInventory,
                                onEdit: () => widget.onEdit(products[i]),
                                onReceiveStock: widget.showInventory &&
                                        widget.onReceiveStock != null
                                    ? () => widget.onReceiveStock!(products[i])
                                    : null,
                              ),
                            )),
    ]);
  }
}

class _ProductListRow extends StatelessWidget {
  const _ProductListRow(
      {required this.product,
      required this.onEdit,
      required this.showInventory,
      this.onReceiveStock});
  final Product product;
  final VoidCallback onEdit;
  final VoidCallback? onReceiveStock;
  final bool showInventory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ProductImage(
                  product: product,
                  width: 56,
                  height: 56,
                  borderRadius: BorderRadius.circular(8)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(product.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${product.category} · บาร์โค้ด: ${product.barcode.isEmpty ? "-" : product.barcode}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('฿${product.effectivePrice.toStringAsFixed(2)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          if (product.isOnSale)
                            Text('฿${product.price.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                    decoration: TextDecoration.lineThrough)),
                          Text('สต็อก ${product.stock}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: showInventory && product.isLowStock
                                      ? cs.error
                                      : cs.onSurfaceVariant)),
                        ]),
                  ])),
              if (onReceiveStock != null)
                IconButton(
                    onPressed: onReceiveStock,
                    tooltip: 'รับสินค้าเข้า',
                    icon: const Icon(Icons.add_box_outlined)),
            ]),
          )),
    );
  }
}
