import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../services/product_service.dart';
import '../services/shop_service.dart';
import 'ingredients_screen.dart';
import 'modifier_groups_screen.dart';
import 'product_form_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _search = '';
  String _category = 'ทั้งหมด';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สินค้า'),
        centerTitle: true,
        actions: [
          // Add-on / modifier groups — labelled so restaurant owners can
          // find it (was a bare icon before). Only for the restaurant tier.
          StreamBuilder<Shop?>(
            stream: ShopService.watchCurrentShop(),
            builder: (context, snap) {
              if (snap.data?.tier != ShopTier.restaurant) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.egg_outlined, size: 18),
                    label: const Text('วัตถุดิบ'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const IngredientsScreen()),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: TextButton.icon(
                      icon: const Icon(Icons.tune_outlined, size: 18),
                      label: const Text('ตัวเลือกเสริม'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ModifierGroupsScreen()),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มสินค้า'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: const InputDecoration(
                hintText: 'ค้นหาสินค้า...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: ['ทั้งหมด', ...ProductService.categories].map((cat) {
                final sel = cat == _category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: sel,
                    onSelected: (_) => setState(() => _category = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<Product>>(
              stream: ProductService.watchAll(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                var products = snap.data!;
                if (_search.isNotEmpty) {
                  products = products
                      .where((p) =>
                          p.name.toLowerCase().contains(_search.toLowerCase()) ||
                          p.barcode.contains(_search))
                      .toList();
                }
                if (_category != 'ทั้งหมด') {
                  products = products.where((p) => p.category == _category).toList();
                }
                if (products.isEmpty) {
                  return const Center(child: Text('ไม่พบสินค้า'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: products.length,
                  itemBuilder: (ctx, i) => _ProductTile(product: products[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  const _ProductTile({required this.product});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: product.isLowStock ? Colors.red.shade100 : Colors.blue.shade100,
          child: Icon(
            Icons.inventory_2_outlined,
            color: product.isLowStock ? Colors.red : Colors.blue,
          ),
        ),
        title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${product.category} · Barcode: ${product.barcode.isEmpty ? "-" : product.barcode}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('฿${product.effectivePrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (product.isOnSale)
                  Text('฿${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        decoration: TextDecoration.lineThrough,
                      )),
                Text(
                  'สต็อก ${product.stock}',
                  style: TextStyle(
                    color: product.isLowStock ? Colors.red : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'รับสินค้าเข้า',
              onPressed: () => _showStockDialog(context),
            ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProductFormScreen(product: product)),
        ),
      ),
    );
  }

  void _showStockDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('รับสินค้าเข้า: ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('สต็อกปัจจุบัน: ${product.stock}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'จำนวนที่รับเข้า',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(ctrl.text) ?? 0;
              if (qty <= 0) return;
              await ProductService.adjustStock(product.id, qty);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('เพิ่มสต็อก ${product.name} +$qty ชิ้น')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}
