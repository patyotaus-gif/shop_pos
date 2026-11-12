import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../utils/money_format.dart';
import 'sale_display_controls.dart';
import 'sale_product_grid.dart';

/// One catalog stream supplies search, categories, favorites and product tiles.
class PosCatalog extends StatefulWidget {
  const PosCatalog(
      {super.key,
      required this.loadProducts,
      required this.onAdd,
      required this.onScan,
      required this.onChooseBundle});
  final Stream<List<Product>> Function() loadProducts;
  final ValueChanged<Product> onAdd;
  final VoidCallback onScan, onChooseBundle;

  @override
  State<PosCatalog> createState() => _PosCatalogState();
}

class _PosCatalogState extends State<PosCatalog> {
  late Stream<List<Product>> _products = widget.loadProducts();
  final _search = TextEditingController();
  // Category values are prefixed so real names cannot collide with built-in tabs.
  String _tab = 'all';
  bool _selectedLocally = false;
  String? _pendingTab;
  bool _saveScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SaleDisplayScope.of(context);
    if (_pendingTab != null &&
        controller?.loaded == true &&
        !controller!.busy &&
        !_saveScheduled) {
      _saveScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saveScheduled = false;
        if (mounted) _persistTab();
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(String tab) {
    setState(() {
      _tab = tab;
      _selectedLocally = true;
      _pendingTab = tab;
    });
    _persistTab();
  }

  Future<void> _persistTab() async {
    final controller = SaleDisplayScope.of(context);
    final tab = _pendingTab;
    if (tab == null ||
        controller == null ||
        !controller.loaded ||
        controller.busy) {
      return;
    }
    _pendingTab = null;
    try {
      await controller.save(controller.value.withCatalogTab(tab));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('จำหมวดที่เลือกไม่ได้ ยังเลือกสินค้าต่อได้')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SaleDisplayScope.of(context);
    return StreamBuilder<List<Product>>(
        stream: _products,
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Product>[];
          final categories = ProductService.categoriesFor(all);
          final saved = !_selectedLocally && controller?.loaded == true
              ? controller!.value.catalogTab
              : _tab;
          final valid = saved == 'all' ||
              saved == 'favorites' ||
              categories.any((c) => saved == 'category:$c');
          final tab = valid ? saved : 'all';
          final query = _search.text.trim().toLowerCase();
          final products = all
              .where((p) =>
                  (tab == 'all' ||
                      (tab == 'favorites' && p.isPinned) ||
                      tab == 'category:${p.category}') &&
                  (query.isEmpty ||
                      p.name.toLowerCase().contains(query) ||
                      p.barcode.toLowerCase().contains(query)))
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

          final search = TextField(
            key: const ValueKey('sales-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                hintText: 'ค้นหาสินค้า',
                prefixIcon: IconButton(
                    tooltip: 'สแกนบาร์โค้ด',
                    icon: const Icon(Icons.barcode_reader),
                    onPressed: widget.onScan),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        tooltip: 'ล้างการค้นหา',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_search.clear))
                    : null,
                isDense: true,
                border: const OutlineInputBorder()),
          );
          final header = Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: LayoutBuilder(builder: (context, constraints) {
                  final settings = SaleDisplayButton(categories: categories);
                  if (constraints.maxWidth < 400 &&
                      MediaQuery.textScalerOf(context).scale(16) > 20) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          search,
                          Align(
                              alignment: Alignment.centerRight, child: settings)
                        ]);
                  }
                  return Row(children: [
                    Expanded(child: search),
                    if (controller != null) ...[
                      const SizedBox(width: 8),
                      settings
                    ]
                  ]);
                })),
            SizedBox(
                height: math.max(
                    48, MediaQuery.textScalerOf(context).scale(18) + 24),
                child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _chip('ทั้งหมด', 'all', tab),
                      _chip('รายการโปรด', 'favorites', tab,
                          icon: Icons.push_pin_outlined),
                      Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                              key: const ValueKey('sales-bundles'),
                              avatar: const Icon(Icons.inventory_2_outlined,
                                  size: 18),
                              label: const Text('ชุดสินค้า'),
                              onPressed: widget.onChooseBundle)),
                      for (final category in categories)
                        _chip(category, 'category:$category', tab),
                    ])),
          ]);
          final Widget body;
          if (snapshot.hasError) {
            body = Center(
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('โหลดสินค้าไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ',
                  textAlign: TextAlign.center),
              OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _products = widget.loadProducts()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่')),
            ])));
          } else if (!snapshot.hasData) {
            body = const Center(child: CircularProgressIndicator());
          } else if (products.isEmpty) {
            body = Center(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        query.isNotEmpty
                            ? 'ไม่พบสินค้าที่ค้นหาในหมวดนี้'
                            : tab == 'favorites'
                                ? 'ยังไม่มีรายการโปรด\nปักหมุดสินค้าได้ที่หน้าสินค้า'
                                : 'ยังไม่มีสินค้าในหมวดนี้',
                        textAlign: TextAlign.center)));
          } else if (query.isNotEmpty) {
            body = ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, i) {
                  final p = products[i];
                  final unavailable = !p.isRecipeMode && p.saleable <= 0;
                  return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        key: ValueKey('sale-search-${p.id}'),
                        enabled: !unavailable,
                        trailing: Icon(unavailable
                            ? Icons.block
                            : Icons.add_circle_outline),
                        title: Text(p.name),
                        subtitle: Text([
                          p.isOnSale
                              ? '${formatBaht(p.effectivePrice)} (ปกติ ${formatBaht(p.price)})'
                              : formatBaht(p.effectivePrice),
                          if (p.barcode.isNotEmpty) 'บาร์โค้ด ${p.barcode}',
                          if (!p.isRecipeMode)
                            'คงเหลือ ${p.saleable} ${p.unit}',
                          if (unavailable) 'หมด',
                        ].join('\n')),
                        onTap: unavailable
                            ? null
                            : () {
                                setState(_search.clear);
                                FocusManager.instance.primaryFocus?.unfocus();
                                widget.onAdd(p);
                              },
                      ));
                });
          } else {
            body = SaleProductGrid(
                products: products,
                itemCount: products.length,
                itemBuilder: (_, i) {
                  final p = products[i];
                  final unavailable = !p.isRecipeMode && p.saleable <= 0;
                  return SaleProductCard(
                      key: ValueKey('sale-product-${p.id}'),
                      product: p,
                      unavailableLabel: unavailable ? 'หมด' : null,
                      onTap: unavailable ? null : () => widget.onAdd(p));
                });
          }
          return NestedScrollView(
              headerSliverBuilder: (_, __) =>
                  [SliverToBoxAdapter(child: header)],
              body: body);
        });
  }

  Widget _chip(String label, String value, String selected, {IconData? icon}) =>
      Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
              key: ValueKey('sales-tab-$value'),
              label: Text(label),
              avatar: icon != null ? Icon(icon, size: 18) : null,
              selected: value == selected,
              onSelected: (_) => _select(value)));
}
