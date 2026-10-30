import '../widgets/content_width.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../utils/money_format.dart';
import '../widgets/promotion_editor.dart';
import 'order_qr_screen.dart';
import 'coupons_screen.dart';
import 'buy_get_screen.dart';
import 'bundles_screen.dart';

class SalesToolsScreen extends StatelessWidget {
  const SalesToolsScreen({super.key, required this.shopType});
  final ShopType shopType;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เครื่องมือส่งเสริมการขาย')),
        body: ContentWidth(
            maxWidth: 1040,
            child: AuthService.isStaff
                ? const Center(
                    child: Text(
                        'เฉพาะเจ้าของร้านที่จัดการเครื่องมือส่งเสริมการขายได้'))
                : ListView(padding: const EdgeInsets.all(16), children: [
                    const Text('เพิ่มยอดขาย',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _tool(
                        context,
                        Icons.inventory_2_outlined,
                        'ชุดสินค้า',
                        'เลือกสินค้าครบชุด รับราคาพิเศษที่เคาน์เตอร์ บิลโต๊ะ และออนไลน์',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BundlesScreen()))),
                    _tool(
                        context,
                        Icons.card_giftcard,
                        'ซื้อแถม',
                        'ซื้อครบจำนวน รับของแถมที่เคาน์เตอร์ บิลโต๊ะ และลิงก์สั่งสินค้า',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const BuyGetScreen()))),
                    _tool(
                        context,
                        Icons.confirmation_number_outlined,
                        'โค้ดส่วนลด',
                        'สร้างโค้ดสำหรับลิงก์สั่งสินค้าและบิลโต๊ะ พร้อมยอดขั้นต่ำและจำนวนสิทธิ์',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const CouponsScreen()))),
                    _tool(
                        context,
                        Icons.local_offer_outlined,
                        'โปรโมชั่นส่วนลด',
                        'เลือกราคาโปรหรือลดเป็นเปอร์เซ็นต์ พร้อมวันสิ้นสุด',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    const PromotionProductsScreen()))),
                    _tool(
                        context,
                        Icons.push_pin_outlined,
                        'สินค้าปักหมุดหน้าขาย',
                        'สร้างปุ่มลัดสินค้าในหน้าขายปลีกและขายกลับบ้าน',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PromotionProductsScreen(
                                    pins: true)))),
                    const SizedBox(height: 24),
                    const Text('ให้ลูกค้าเข้าถึงร้าน',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _tool(
                        context,
                        Icons.qr_code_2,
                        'แชร์ลิงก์และ QR ร้าน',
                        'ส่งลิงก์ให้ลูกค้าหรือพิมพ์ QR สำหรับสั่งสินค้า',
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    OrderQrScreen(shopType: shopType)))),
                  ])),
      );

  Widget _tool(BuildContext context, IconData icon, String title,
          String description, VoidCallback onTap) =>
      Card(
          child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(description)),
              trailing: const Icon(Icons.chevron_right),
              onTap: onTap));
}

class PromotionProductsScreen extends StatefulWidget {
  const PromotionProductsScreen({super.key, this.pins = false});
  final bool pins;

  @override
  State<PromotionProductsScreen> createState() =>
      _PromotionProductsScreenState();
}

class _PromotionProductsScreenState extends State<PromotionProductsScreen> {
  late final Stream<List<Product>> _products;
  String _query = '';
  bool _onlyPromotions = false;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _products = AuthService.isStaff
        ? Stream.value(const [])
        : ProductService.watchAll();
  }

  Future<void> _edit(Product product) async {
    final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PromotionEditor(
            product: product,
            onSave: (price, until) => ProductService.setPromotion(product,
                salePrice: price, saleUntil: until)));
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('บันทึกโปรโมชั่นแล้ว')));
    }
  }

  Future<void> _pin(Product product, bool value) async {
    setState(() => _busy.add(product.id));
    try {
      await ProductService.setPinned(product.id, value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(product.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(widget.pins ? 'สินค้าปักหมุดหน้าขาย' : 'โปรโมชั่นส่วนลด')),
        body: ContentWidth(
            maxWidth: 1040,
            child: AuthService.isStaff
                ? const Center(child: Text('เฉพาะเจ้าของร้าน'))
                : Column(children: [
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                            decoration: const InputDecoration(
                                labelText: 'ค้นหาชื่อสินค้าหรือหมวดหมู่',
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder()),
                            onChanged: (value) => setState(
                                () => _query = value.trim().toLowerCase()))),
                    if (!widget.pins)
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: FilterChip(
                                  label: const Text('เฉพาะสินค้าที่ตั้งโปรไว้'),
                                  selected: _onlyPromotions,
                                  onSelected: (value) => setState(
                                      () => _onlyPromotions = value)))),
                    Expanded(
                        child: StreamBuilder<List<Product>>(
                            stream: _products,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const Center(
                                    child: Text(
                                        'โหลดสินค้าไม่สำเร็จ กรุณากลับมาเปิดหน้านี้ใหม่'));
                              }
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }
                              final products = snapshot.data!
                                  .where((p) =>
                                      (p.name.toLowerCase().contains(_query) ||
                                          p.category
                                              .toLowerCase()
                                              .contains(_query)) &&
                                      (widget.pins ||
                                          !_onlyPromotions ||
                                          p.salePrice != null))
                                  .toList();
                              if (products.isEmpty) {
                                return Center(
                                    child: Text(snapshot.data!.isEmpty
                                        ? 'เพิ่มสินค้าที่หน้า สินค้า ก่อนตั้งโปรโมชั่น'
                                        : 'ไม่พบสินค้าที่ตรงกับตัวกรอง'));
                              }
                              return ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: products.length,
                                  itemBuilder: (context, index) {
                                    final p = products[index];
                                    final until = p.saleUntil;
                                    final status = p.salePrice == null
                                        ? 'ยังไม่ตั้งโปรโมชั่น'
                                        : p.isOnSale
                                            ? 'กำลังใช้โปรโมชั่น'
                                            : until != null &&
                                                    !until
                                                        .isAfter(DateTime.now())
                                                ? 'โปรโมชั่นหมดอายุ'
                                                : 'ราคาโปรไม่ต่ำกว่าราคาปกติ';
                                    return Card(
                                        child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(p.name,
                                                      style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  Text(
                                                      '${p.category} · ราคาปกติ ${formatBaht(p.price)}'),
                                                  if (widget.pins)
                                                    SwitchListTile(
                                                        contentPadding:
                                                            EdgeInsets.zero,
                                                        title: const Text(
                                                            'ปักหมุดหน้าขาย'),
                                                        value: p.isPinned,
                                                        onChanged: _busy
                                                                .contains(p.id)
                                                            ? null
                                                            : (value) =>
                                                                _pin(p, value))
                                                  else ...[
                                                    const SizedBox(height: 8),
                                                    Text(status),
                                                    if (p.salePrice != null)
                                                      Text(
                                                          'ราคาโปร ${formatBaht(p.salePrice!)}'),
                                                    if (p.salePrice != null)
                                                      Text(until == null
                                                          ? 'ไม่กำหนดวันสิ้นสุด'
                                                          : 'ถึง ${until.day}/${until.month}/${until.year} สิ้นวัน'),
                                                    const SizedBox(height: 8),
                                                    OutlinedButton.icon(
                                                        icon: const Icon(Icons
                                                            .edit_outlined),
                                                        label: Text(p
                                                                    .salePrice ==
                                                                null
                                                            ? 'ตั้งโปรโมชั่น'
                                                            : 'แก้ไข / ยกเลิกโปรโมชั่น'),
                                                        onPressed: () =>
                                                            _edit(p)),
                                                  ],
                                                ])));
                                  });
                            })),
                  ])),
      );
}
