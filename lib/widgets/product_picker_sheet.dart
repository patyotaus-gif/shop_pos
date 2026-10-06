import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import 'sale_product_grid.dart';

/// Bottom sheet that lets the cashier pick a product to add to a table tab.
/// Supports search + category chips; tap a product to return it via Navigator.
///
/// Why a sheet (not a full screen): keeps the table-order context visible
/// behind it — cashier sees totals/items while picking the next dish.
Future<Product?> showProductPicker(BuildContext context) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ProductPickerSheet(),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';
  String _category = 'ทั้งหมด';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Text('เลือกสินค้า',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: false,
                decoration: const InputDecoration(
                  hintText: 'ค้นหา...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Product>>(
                stream: ProductService.watchAll(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data ?? const <Product>[];
                  final categories = <String>{
                    'ทั้งหมด',
                    ...all.map((p) => p.category),
                  }.toList();

                  final filtered = all.where((p) {
                    if (_category != 'ทั้งหมด' && p.category != _category) {
                      return false;
                    }
                    if (_query.isEmpty) return true;
                    return p.name.toLowerCase().contains(_query) ||
                        p.barcode.toLowerCase().contains(_query);
                  }).toList();

                  return Column(
                    children: [
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (_, i) {
                            final c = categories[i];
                            final selected = c == _category;
                            return ChoiceChip(
                              label: Text(c),
                              selected: selected,
                              onSelected: (_) => setState(() => _category = c),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text('ไม่พบสินค้า',
                                    style: TextStyle(
                                        color: cs.onSurface
                                            .withValues(alpha: 0.5))))
                            : SaleProductGrid(
                                controller: scrollCtrl,
                                itemCount: filtered.length,
                                itemBuilder: (_, i) => SaleProductCard(
                                  product: filtered[i],
                                  onTap: () =>
                                      Navigator.pop(context, filtered[i]),
                                ),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
