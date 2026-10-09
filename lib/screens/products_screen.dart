import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/auth_service.dart';
import '../widgets/product_catalog.dart';
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
  late final Stream<Shop?> _shop;
  late final Stream<List<Product>> _products;
  late final String _preferenceKey;

  @override
  void initState() {
    super.initState();
    _shop = ShopService.watchCurrentShop()
        .asBroadcastStream(onCancel: (subscription) => subscription.cancel());
    _products = ProductService.watchAll();
    _preferenceKey = 'product-catalog-layout:${AuthService.shopId}';
  }

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
            stream: _shop,
            builder: (context, snap) {
              if (snap.data?.shopType != ShopType.restaurant) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (Entitlements.canUseRecipes(
                      snap.data!.tier, snap.data!.shopType))
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
      body: StreamBuilder<Shop?>(
        stream: _shop,
        builder: (context, shopSnap) => StreamBuilder<List<Product>>(
          stream: _products,
          builder: (context, snap) => ProductCatalog(
            products: snap.data ?? const [],
            categories: ProductService.categories,
            preferenceKey: _preferenceKey,
            loading: !snap.hasData && !snap.hasError,
            hasError: snap.hasError,
            showInventory: shopSnap.hasData &&
                Entitlements.canUseInventory(shopSnap.data!.tier),
            onEdit: (product) => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProductFormScreen(product: product))),
            onReceiveStock: (product) => _showStockDialog(context, product),
          ),
        ),
      ),
    );
  }

  void _showStockDialog(BuildContext context, Product product) {
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(ctrl.text) ?? 0;
              if (qty <= 0) return;
              await ProductService.adjustStock(product.id, qty);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text('เพิ่มสต็อก ${product.name} +$qty ชิ้น')),
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
