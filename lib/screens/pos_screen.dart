import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/cart_item.dart';
import '../models/customer.dart';
import '../models/sale.dart';
import '../models/staff_member.dart';
import '../services/customer_service.dart';
import '../services/entitlements.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/settings_service.dart';
import '../services/shop_service.dart';
import '../services/staff_service.dart';
import '../utils/receipt_generator.dart';
import '../widgets/payment_sheet.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _baht = NumberFormat('#,##0.00', 'th_TH');
  final List<CartItem> _cart = [];
  double _discount = 0;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  String _selectedCategory = 'ทั้งหมด';

  // Staff attribution (Full/Restaurant). `_staffEnabled` gates the app-bar
  // chip; `_activeStaffName` rides along on each sale.
  bool _staffEnabled = false;
  String? _activeStaffName;

  // Loyalty (Full/Restaurant). `_loyaltyEnabled` gates the attach-customer
  // button; `_loyaltyCustomer` is the customer attached to the current
  // cart, cleared after each sale.
  bool _loyaltyEnabled = false;
  Customer? _loyaltyCustomer;

  @override
  void initState() {
    super.initState();
    _loadShopContext();
  }

  Future<void> _loadShopContext() async {
    final shop = await ShopService.getCurrentShop();
    if (shop == null) return;
    final staffEnabled = Entitlements.canUseStaff(shop.tier);
    final active = staffEnabled ? await StaffService.getActive() : null;
    if (mounted) {
      setState(() {
        _staffEnabled = staffEnabled;
        _activeStaffName = active?.name;
        _loyaltyEnabled = Entitlements.canUseLoyalty(shop.tier);
      });
    }
  }

  /// Attach a loyalty customer to the current cart by phone. Finds an
  /// existing customer or creates one, then shows their points.
  Future<void> _attachCustomer() async {
    final phoneCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลูกค้าสะสมแต้ม'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทร',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อ (ถ้าเป็นลูกค้าใหม่)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('เลือก')),
        ],
      ),
    );
    if (ok != true || phoneCtrl.text.trim().isEmpty || !mounted) return;
    final customer = await CustomerService.ensure(
        phone: phoneCtrl.text, name: nameCtrl.text);
    if (mounted) {
      setState(() => _loyaltyCustomer = customer);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'ลูกค้า ${customer.name} · ${customer.points} แต้ม')),
      );
    }
  }

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

  Future<void> _openScanner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ScannerScreen(
          onScan: (barcode) async {
            final product = await ProductService.getByBarcode(barcode);
            if (!mounted) return null;
            if (product != null) {
              _addToCart(product);
              return product.name;
            }
            return null;
          },
        ),
      ),
    );
  }


  Future<void> _checkout({bool isDebt = false}) async {
    if (_cart.isEmpty) return;

    // ตรวจ stock ก่อน checkout
    for (final item in _cart) {
      if (item.product.stock < item.quantity) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${item.product.name}: stock ไม่พอ (เหลือ ${item.product.stock} ชิ้น)'),
            backgroundColor: Colors.red,
          ));
        }
        return;
      }
    }

    String? customerName;
    if (isDebt) {
      customerName = await _askCustomerName();
      if (customerName == null) return;
    }

    double paid = 0.0;
    PaymentMethod method = _paymentMethod;
    if (!isDebt) {
      // Ask for payment method + amount in one sheet, instead of forcing
      // the cashier to pick a method before they hit "ชำระเงิน".
      final result = await showPaymentSheet(context, total: _total);
      if (result == null) return;
      method = result.method;
      paid = result.paid;
      setState(() => _paymentMethod = method);
    }

    try {
      final sale = await SaleService.checkout(
        cart: _cart,
        paid: paid,
        discount: _discount,
        isDebt: isDebt,
        customerName: customerName,
        paymentMethod: method,
        staffName: _activeStaffName,
        loyaltyCustomerId: _loyaltyCustomer?.id,
      );

      setState(() {
        _cart.clear();
        _discount = 0;
        _loyaltyCustomer = null;
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
              final shopName = await SettingsService.getShopName();
              await ReceiptGenerator.printReceipt(sale, shopName: shopName);
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
    if (result != null) {
      setState(() => _discount = result.clamp(0.0, _subtotal));
    }
  }

  /// Switch the active staff at the till. Lists staff profiles; tapping
  /// one asks for that staff's 4-digit PIN to confirm (so a cashier can
  /// only clock in as themselves). Attribution, not hard security.
  Future<void> _switchStaff() async {
    final staff = await StaffService.getAll();
    if (!mounted) return;
    if (staff.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ยังไม่มีพนักงาน — เพิ่มได้ที่ ตั้งค่า → พนักงาน')),
      );
      return;
    }
    final picked = await showModalBottomSheet<StaffMember>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StaffPickerSheet(staff: staff),
    );
    if (picked != null && mounted) {
      await StaffService.setActive(picked);
      setState(() => _activeStaffName = picked.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS'),
        centerTitle: true,
        actions: [
          if (_staffEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar:
                    Icon(Icons.person_outline, size: 18, color: cs.primary),
                label: Text(_activeStaffName ?? 'เลือกพนักงาน',
                    style: const TextStyle(fontSize: 12)),
                onPressed: _switchStaff,
              ),
            ),
          IconButton(
            // Barcode scanner — was incorrectly using a QR icon.
            icon: const Icon(Icons.barcode_reader),
            tooltip: 'สแกนบาร์โค้ด',
            onPressed: _openScanner,
          ),
        ],
      ),
      body: Column(
        children: [
          // Product search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _ProductSearch(
              onSelected: _addToCart,
              selectedCategory: _selectedCategory,
            ),
          ),
          // Category filter chips
          StreamBuilder<List<Product>>(
            stream: ProductService.watchAll(),
            builder: (ctx, snap) {
              final cats = ['ทั้งหมด', ...ProductService.categories];
              return SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: cats.map((cat) {
                    final sel = cat == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = cat),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Pinned products (always horizontal, always visible)
          StreamBuilder<List<Product>>(
            stream: ProductService.watchAll(),
            builder: (ctx, snap) {
              final all = snap.data ?? [];
              final pinned = all
                  .where((p) =>
                      p.isPinned &&
                      (_selectedCategory == 'ทั้งหมด' ||
                          p.category == _selectedCategory))
                  .toList();
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
                      label: Text(pinned[i].name,
                          style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.push_pin, size: 14),
                      onPressed: () => _addToCart(pinned[i]),
                    ),
                  ),
                ),
              );
            },
          ),
          // Category-filtered product picker (only when a specific
          // category is selected — keeps "ทั้งหมด" view clean and lets
          // pinned + search carry the load there). Image cards with promo
          // badges; tap = add 1 to cart (no sheet — cashier speed).
          if (_selectedCategory != 'ทั้งหมด')
            StreamBuilder<List<Product>>(
              stream: ProductService.watchAll(),
              builder: (ctx, snap) {
                final all = snap.data ?? [];
                final inCategory = all
                    .where((p) => p.category == _selectedCategory)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                if (inCategory.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'ยังไม่มีสินค้าในหมวด "$_selectedCategory"',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  );
                }
                return SizedBox(
                  height: 132,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    itemCount: inCategory.length,
                    itemBuilder: (ctx, i) {
                      final p = inCategory[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PickerProductCard(
                          product: p,
                          onAdd: p.stock <= 0 ? null : () => _addToCart(p),
                        ),
                      );
                    },
                  ),
                );
              },
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
          // Loyalty customer strip (Full/Restaurant). Tap to attach a
          // customer by phone so the sale accrues points.
          if (_loyaltyEnabled)
            Material(
              color: _loyaltyCustomer != null
                  ? cs.primary.withValues(alpha: 0.06)
                  : cs.surface,
              child: InkWell(
                onTap: _attachCustomer,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(color: cs.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.card_giftcard_outlined,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _loyaltyCustomer != null
                              ? '${_loyaltyCustomer!.name} · ${_loyaltyCustomer!.points} แต้ม'
                              : 'เพิ่มลูกค้าสะสมแต้ม',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: _loyaltyCustomer != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: cs.onSurface),
                        ),
                      ),
                      if (_loyaltyCustomer != null)
                        GestureDetector(
                          onTap: () =>
                              setState(() => _loyaltyCustomer = null),
                          child: Icon(Icons.close,
                              size: 18,
                              color: cs.onSurface.withValues(alpha: 0.5)),
                        )
                      else
                        Icon(Icons.add, size: 18, color: cs.primary),
                    ],
                  ),
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
  final String selectedCategory;
  const _ProductSearch({required this.onSelected, this.selectedCategory = 'ทั้งหมด'});

  @override
  State<_ProductSearch> createState() => _ProductSearchState();
}

class _ProductSearchState extends State<_ProductSearch> {
  final _ctrl = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _results = [];
  StreamSubscription<List<Product>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ProductService.watchAll().listen((products) {
      setState(() => _allProducts = products);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    if (q.isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() {
      _results = _allProducts
          .where((p) =>
              (widget.selectedCategory == 'ทั้งหมด' ||
                  p.category == widget.selectedCategory) &&
              (p.name.toLowerCase().contains(q.toLowerCase()) ||
                  p.barcode.contains(q)))
          .take(5)
          .toList();
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
                        leading: p.imagePath != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.file(
                                  File(p.imagePath!),
                                  width: 40, height: 40, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, size: 40),
                                ),
                              )
                            : null,
                        title: Text(p.name),
                        subtitle: Text(p.isOnSale
                            ? '฿${p.effectivePrice.toStringAsFixed(2)} (ปกติ ฿${p.price.toStringAsFixed(2)}) · สต็อก ${p.stock}'
                            : '฿${p.price.toStringAsFixed(2)} · สต็อก ${p.stock}'),
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
        leading: item.product.imagePath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(item.product.imagePath!),
                  width: 44, height: 44, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 44),
                ),
              )
            : null,
        title: Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('฿${baht.format(item.product.effectivePrice)} × ${item.quantity}'),
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
            GestureDetector(
              onTap: () async {
                final ctrl = TextEditingController(text: '${item.quantity}');
                final result = await showDialog<int>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('จำนวน'),
                    content: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: const Text('ยกเลิก')),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text)),
                        child: const Text('ตกลง'),
                      ),
                    ],
                  ),
                );
                if (result != null) onQtyChanged(result);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
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

/// Compact product card for the POS category picker. Tap = add 1 to cart.
/// [onAdd] == null renders the out-of-stock state (faded + "หมด").
class _PickerProductCard extends StatelessWidget {
  const _PickerProductCard({required this.product, this.onAdd});
  final Product product;
  final VoidCallback? onAdd;

  Widget _fallbackIcon(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.inventory_2_outlined,
            size: 24, color: cs.onSurface.withValues(alpha: 0.3)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final out = onAdd == null;
    final pct = product.discountPercent;

    Widget image;
    if (product.imagePath != null) {
      image = Image.file(
        File(product.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(cs),
      );
    } else if ((product.imageUrl ?? '').isNotEmpty) {
      image = Image.network(
        product.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(cs),
      );
    } else {
      image = _fallbackIcon(cs);
    }

    return SizedBox(
      width: 110,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAdd,
          child: Opacity(
            opacity: out ? 0.45 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      if (pct > 0)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7A1F2B),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'ลด $pct%',
                              style: const TextStyle(
                                color: Color(0xFFF5F1EC),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (out)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7A1F2B),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'หมด',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 27,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '฿${product.effectivePrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          if (product.isOnSale)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '฿${product.price.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  decoration: TextDecoration.lineThrough,
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

    return SafeArea(
      top: false,
      child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              // All three buttons share the row evenly (1:1:2) so the
              // narrowest one ("เชื่อ") still has enough horizontal room
              // not to wrap on Android, where the default Thai font is
              // wider than iOS's Thonburi/SF.
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDiscount,
                  icon: const Icon(Icons.discount_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ส่วนลด', maxLines: 1, softWrap: false),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasItems ? onDebt : null,
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('เชื่อ', maxLines: 1, softWrap: false),
                  ),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: hasItems ? onCheckout : null,
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ชำระเงิน', maxLines: 1, softWrap: false),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ));
  }
}

// ── Full-screen scanner ─────────────────────────────────────────
class _ScannerScreen extends StatefulWidget {
  /// Returns product name if found, null if not found.
  final Future<String?> Function(String barcode) onScan;
  const _ScannerScreen({required this.onScan});

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _ctrl;
  late final AnimationController _lineCtrl;
  late final Animation<double> _lineAnim;
  bool _torchOn = false;
  bool _busy = false;
  Timer? _bannerTimer;
  late final AudioPlayer _audio;
  String? _beepPath;

  String? _bannerMsg;
  bool _bannerSuccess = false;
  bool _bannerVisible = false;

  // Generates a short 880Hz beep WAV in memory — no asset file needed
  static Uint8List _generateBeep() {
    const sampleRate = 44100;
    const freq = 3500;   // supermarket scanner ~3500Hz
    const durationMs = 80;
    const numSamples = sampleRate * durationMs ~/ 1000;
    const dataSize = numSamples * 2;

    final buf = ByteData(44 + dataSize);
    for (final e in [
      [0, 0x52], [1, 0x49], [2, 0x46], [3, 0x46],
      [8, 0x57], [9, 0x41], [10, 0x56], [11, 0x45],
      [12, 0x66], [13, 0x6D], [14, 0x74], [15, 0x20],
      [36, 0x64], [37, 0x61], [38, 0x74], [39, 0x61],
    ]) { buf.setUint8(e[0], e[1]); }
    buf.setUint32(4, 36 + dataSize, Endian.little);
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little);
    buf.setUint16(22, 1, Endian.little);
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    buf.setUint32(40, dataSize, Endian.little);
    // attack คมทันที, decay เร็ว (เหมือน barcode scanner จริง)
    for (var i = 0; i < numSamples; i++) {
      final attack = i < 20 ? i / 20.0 : 1.0;
      final decay = (numSamples - i) / numSamples.toDouble();
      final env = attack * decay;
      final s = (sin(2 * pi * freq * i / sampleRate) * 0.65 * env * 32767).round().clamp(-32768, 32767);
      buf.setInt16(44 + i * 2, s, Endian.little);
    }
    return buf.buffer.asUint8List();
  }

  Future<void> _initBeep() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pokpok_beep.wav');
    await file.writeAsBytes(_generateBeep());
    _beepPath = file.path;
  }

  @override
  void initState() {
    super.initState();
    _audio = AudioPlayer();
    _initBeep();
    _ctrl = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.qrCode,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
      autoStart: true,
    );
    _lineCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _lineAnim = CurvedAnimation(parent: _lineCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _audio.dispose();
    _ctrl.dispose();
    _lineCtrl.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null) return;

    _busy = true;
    HapticFeedback.mediumImpact();
    if (_beepPath != null) unawaited(_audio.play(DeviceFileSource(_beepPath!)));

    final productName = await widget.onScan(value);
    if (!mounted) return;

    // Cancel previous timer and show new banner
    _bannerTimer?.cancel();
    setState(() {
      _bannerSuccess = productName != null;
      _bannerMsg = productName != null
          ? 'เพิ่ม "$productName" ลงตะกร้าแล้ว'
          : 'ไม่พบสินค้า (barcode: $value)';
      _bannerVisible = true;
    });

    // Auto-dismiss after 2s then allow next scan
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _bannerVisible = false);
      Future.delayed(const Duration(milliseconds: 300), () => _busy = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanW = size.width - 40;
    const scanH = 160.0;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanW,
      height: scanH,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera feed (full screen)
          MobileScanner(
            controller: _ctrl,
            onDetect: _onDetect,
            scanWindow: scanRect,
          ),

          // Dark overlay with cutout
          CustomPaint(
            size: Size(size.width, size.height),
            painter: _OverlayPainter(scanRect),
          ),

          // Animated scan line
          Positioned(
            left: scanRect.left + 2,
            width: scanRect.width - 4,
            top: scanRect.top + 2,
            height: scanRect.height - 4,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _lineAnim,
                builder: (_, __) => Align(
                  alignment: Alignment(0, _lineAnim.value * 2 - 1),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        const Color(0xFF7A1F2B).withValues(alpha: 0.9),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Top area: nav bar + banner stacked in a Column inside SafeArea
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nav bar row
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'สแกนบาร์โค้ด',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _torchOn ? Icons.flashlight_on : Icons.flashlight_off,
                          color: _torchOn ? Colors.yellow : Colors.white,
                        ),
                        onPressed: () {
                          _ctrl.toggleTorch();
                          setState(() => _torchOn = !_torchOn);
                        },
                      ),
                    ],
                  ),
                  // Banner — slides in right below nav bar
                  AnimatedSize(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOut,
                    child: _bannerVisible
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _bannerSuccess
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _bannerSuccess ? Icons.check_circle : Icons.error_outline,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _bannerMsg ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom hint
          Positioned(
            bottom: 72, left: 0, right: 0,
            child: Column(children: [
              const Text(
                'จ่อกล้องที่บาร์โค้ดในกรอบ',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'ระบบสแกนอัตโนมัติ ไม่ต้องกดปุ่ม',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Scanner overlay painter ─────────────────────────────────────
class _OverlayPainter extends CustomPainter {
  final Rect scanRect;
  _OverlayPainter(this.scanRect);

  @override
  void paint(Canvas canvas, Size size) {
    // Dark overlay with hole
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(12))),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    // Corner brackets
    final p = Paint()
      ..color = const Color(0xFF7A1F2B)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const len = 22.0;
    final r = scanRect;

    // Top-left
    canvas.drawLine(Offset(r.left, r.top + len), r.topLeft, p);
    canvas.drawLine(r.topLeft, Offset(r.left + len, r.top), p);
    // Top-right
    canvas.drawLine(Offset(r.right - len, r.top), r.topRight, p);
    canvas.drawLine(r.topRight, Offset(r.right, r.top + len), p);
    // Bottom-left
    canvas.drawLine(Offset(r.left, r.bottom - len), r.bottomLeft, p);
    canvas.drawLine(r.bottomLeft, Offset(r.left + len, r.bottom), p);
    // Bottom-right
    canvas.drawLine(Offset(r.right - len, r.bottom), r.bottomRight, p);
    canvas.drawLine(r.bottomRight, Offset(r.right, r.bottom - len), p);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.scanRect != scanRect;
}

/// Staff picker for the POS till. Tap a name → enter their 4-digit PIN →
/// returns the matched StaffMember (or null on cancel/wrong PIN).
class _StaffPickerSheet extends StatefulWidget {
  const _StaffPickerSheet({required this.staff});
  final List<StaffMember> staff;

  @override
  State<_StaffPickerSheet> createState() => _StaffPickerSheetState();
}

class _StaffPickerSheetState extends State<_StaffPickerSheet> {
  StaffMember? _selected;
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _confirm() {
    if (_pin.text.trim() == _selected!.pin) {
      Navigator.pop(context, _selected);
    } else {
      setState(() => _error = 'PIN ไม่ถูกต้อง');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_selected == null ? 'ใครกำลังขาย?' : 'ใส่ PIN ของ ${_selected!.name}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_selected == null)
            ...widget.staff.map((s) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: cs.primary.withValues(alpha: 0.12),
                    child: Text(
                      s.name.isNotEmpty ? s.name.characters.first : '?',
                      style: TextStyle(
                          color: cs.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(s.name),
                  subtitle: Text(s.role.label),
                  onTap: () => setState(() => _selected = s),
                ))
          else ...[
            TextField(
              controller: _pin,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              obscureText: true,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: 'PIN 4 หลัก',
                errorText: _error,
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    _selected = null;
                    _pin.clear();
                    _error = null;
                  }),
                  child: const Text('กลับ'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _confirm,
                  child: const Text('ยืนยัน'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
