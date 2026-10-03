import '../widgets/cart_item_tile.dart';
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
import '../services/customer_service.dart';
import '../services/entitlements.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/shop_service.dart';
import '../services/auth_service.dart';
import '../services/staff_access_service.dart';
import 'user_switch_screen.dart';
import 'offline_cash_screen.dart';
import 'sale_receipt_screen.dart';
import '../widgets/payment_sheet.dart';
import '../widgets/modifier_picker_sheet.dart';
import '../models/order_modifier.dart';
import '../widgets/shop_operation.dart';
import '../utils/operation_error.dart';
import '../widgets/product_image.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartItem> _cart = [];
  double _discount = 0;
  bool _checkoutBusy = false;
  bool _checkingPending = true;
  Sale? _pendingSale;
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
    _loadPending();
  }

  Future<void> _loadShopContext() async {
    try {
      final shop = await ShopService.getCurrentShop();
      if (shop == null) return;
      final staffEnabled =
          !AuthService.isStaff && Entitlements.canUseStaff(shop.tier);
      final name = AuthService.isStaff
          ? (await StaffAccessService.workspace())['staffName'] as String?
          : 'เจ้าของร้าน';
      if (mounted) {
        setState(() {
          _staffEnabled = staffEnabled;
          _activeStaffName = name;
          _loyaltyEnabled =
              !AuthService.isStaff && Entitlements.canUseLoyalty(shop.tier);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(e))));
      }
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
            content: Text('ลูกค้า ${customer.name} · ${customer.points} แต้ม')),
      );
    }
  }

  double get _subtotal => _cart.fold(0, (s, e) => s + e.subtotal);
  double get _total => _subtotal - _discount;

  Future<void> _addToCart(Product product) async {
    if (_checkoutBusy || _pendingSale != null) return;
    ModifierPick? pick;
    if (product.modifierGroupIds.isNotEmpty) {
      pick = await showModifierPicker(context, product: product);
      if (pick == null || !mounted || _checkoutBusy) return;
    }
    final modifiers = pick?.modifiers ?? <OrderModifier>[];
    final notes = pick?.notes;
    setState(() {
      final idx = _cart.indexWhere((e) =>
          e.product.id == product.id &&
          modifiersEqual(e.modifiers, modifiers) &&
          e.notes == notes);
      if (idx >= 0) {
        _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity + 1);
      } else {
        _cart.add(
            CartItem(product: product, modifiers: modifiers, notes: notes));
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
              await _addToCart(product);
              return product.name;
            }
            return null;
          },
        ),
      ),
    );
  }

  Future<void> _loadPending() async {
    try {
      final pending = await SaleService.pendingCheckout();
      if (mounted) {
        setState(() {
          _pendingSale = pending;
          _checkingPending = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _checkingPending = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(error))));
      }
    }
  }

  Future<void> _checkout({bool isDebt = false}) async {
    if (AuthService.isStaff && isDebt) return;
    if (_checkoutBusy ||
        _checkingPending ||
        (_cart.isEmpty && _pendingSale == null)) {
      return;
    }
    setState(() => _checkoutBusy = true);
    try {
      final retry = _pendingSale != null;
      String? customerName;
      double paid = 0;
      var method = _paymentMethod;
      var channel = SalesChannel.storefront;
      if (!retry) {
        if (isDebt) {
          customerName = await _askCustomerName();
          if (customerName == null || !mounted) return;
        } else {
          final result = await showPaymentSheet(context, total: _total);
          if (result == null || !mounted) return;
          method = result.method;
          channel = result.salesChannel;
          paid = result.paid;
        }
      }
      if (!mounted) return;
      final frozenCart = List<CartItem>.unmodifiable(_cart);
      final sale = await runShopOperation(
          context,
          () => retry
              ? SaleService.resumeCheckout()
              : SaleService.checkout(
                  cart: frozenCart,
                  paid: paid,
                  discount: _discount,
                  isDebt: isDebt,
                  customerName: customerName,
                  paymentMethod: method,
                  salesChannel: channel,
                  staffName: _activeStaffName,
                  loyaltyCustomerId: _loyaltyCustomer?.id));
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _discount = 0;
        _loyaltyCustomer = null;
        _pendingSale = null;
        _paymentMethod = method;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('บันทึกการขายแล้ว')));
      _showReceiptDialog(sale);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(error))));
      }
    } finally {
      await _loadPending();
      if (mounted) setState(() => _checkoutBusy = false);
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
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
    Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => SaleReceiptScreen(sale: sale)));
  }

  Future<void> _setDiscount() async {
    final ctrl =
        TextEditingController(text: _discount > 0 ? _discount.toString() : '');
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, 0.0),
              child: const Text('ล้างส่วนลด')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _discount = result.clamp(0.0, _subtotal));
    }
  }

  /// Hand off to a separate authenticated cashier session after PIN validation.
  Future<void> _switchStaff() async {
    if (_cart.isNotEmpty || _pendingSale != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ปิดบิลหรือเคลียร์ตะกร้าก่อนเปลี่ยนผู้ใช้')));
      return;
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const UserSwitchScreen()));
  }

  Widget _productCatalog(bool grid) => StreamBuilder<List<Product>>(
      stream: ProductService.watchAll(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('โหลดสินค้าไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data!
            .where((p) =>
                _selectedCategory == 'ทั้งหมด' ||
                p.category == _selectedCategory)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        if (products.isEmpty) {
          return const Center(child: Text('ยังไม่มีสินค้าในหมวดนี้'));
        }
        Widget card(int i) => _PickerProductCard(
            product: products[i],
            onAdd:
                products[i].stock <= 0 ? null : () => _addToCart(products[i]));
        if (grid) {
          return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: 148,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12),
              itemCount: products.length,
              itemBuilder: (_, i) => card(i));
        }
        return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            itemCount: products.length,
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) => card(i));
      });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ขายหน้าร้าน'),
        centerTitle: true,
        actions: [
          if (_staffEnabled)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: Icon(Icons.person_outline, size: 18, color: cs.primary),
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
      body: Column(children: [
        if (!_checkoutBusy && _pendingSale == null && _cart.isEmpty)
          const OfflineEntryButton(allowPrepare: true),
        if (_checkingPending) const LinearProgressIndicator(),
        if (_pendingSale != null)
          Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        'มีบิลรอยืนยัน ฿${_pendingSale!.total.toStringAsFixed(2)} อย่ารับเงินซ้ำ ตรวจรายการเดิมก่อนเริ่มบิลใหม่'),
                    FilledButton.icon(
                        onPressed: _checkoutBusy ? null : () => _checkout(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('ตรวจและยืนยันรายการเดิม')),
                  ])),
        Expanded(
            child: AbsorbPointer(
                absorbing:
                    _checkoutBusy || _checkingPending || _pendingSale != null,
                child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final controls = <Widget>[
                    // Product search
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            children: cats.map((cat) {
                              final sel = cat == _selectedCategory;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(cat,
                                      style: const TextStyle(fontSize: 12)),
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
                  ];
                  final basket = Column(children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(children: [
                          const Icon(Icons.shopping_cart_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text('รายการขาย',
                              style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          Text('${_cart.length} รายการ')
                        ])),
                    // Cart
                    Expanded(
                      child: _cart.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_cart_outlined,
                                      size: 64,
                                      color:
                                          cs.onSurface.withValues(alpha: 0.3)),
                                  const SizedBox(height: 8),
                                  Text('ยังไม่มีสินค้าในตะกร้า',
                                      style: TextStyle(
                                          color: cs.onSurface
                                              .withValues(alpha: 0.4))),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _cart.length,
                              itemBuilder: (ctx, i) => CartItemTile(
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
                                        color: cs.onSurface
                                            .withValues(alpha: 0.5)),
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
                  ]);
                  if (wide) {
                    return Row(children: [
                      Expanded(
                          child: Column(children: [
                        ...controls,
                        Expanded(child: _productCatalog(true))
                      ])),
                      const VerticalDivider(width: 1),
                      SizedBox(width: 380, child: basket),
                    ]);
                  }
                  return Column(children: [
                    ...controls,
                    if (constraints.maxHeight >= 580)
                      SizedBox(height: 148, child: _productCatalog(false)),
                    Expanded(child: basket),
                  ]);
                }))),
      ]),
    );
  }
}

// --- Sub-widgets ---

class _ProductSearch extends StatefulWidget {
  final ValueChanged<Product> onSelected;
  final String selectedCategory;
  const _ProductSearch(
      {required this.onSelected, this.selectedCategory = 'ทั้งหมด'});

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
                        leading: (p.imagePath != null ||
                                (p.imageUrl ?? '').isNotEmpty)
                            ? ProductImage(
                                product: p,
                                width: 40,
                                height: 40,
                                borderRadius: BorderRadius.circular(6),
                              )
                            : null,
                        title: Text(p.name),
                        subtitle: Text(p.isOnSale
                            ? '฿${p.effectivePrice.toStringAsFixed(2)} (ปกติ ฿${p.price.toStringAsFixed(2)}) · สต็อก ${p.stock}'
                            : '฿${p.price.toStringAsFixed(2)} · สต็อก ${p.stock}'),
                        trailing: Text(p.barcode,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey)),
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

/// Compact product card for the POS category picker. Tap = add 1 to cart.
/// [onAdd] == null renders the out-of-stock state (faded + "หมด").
class _PickerProductCard extends StatelessWidget {
  const _PickerProductCard({required this.product, this.onAdd});
  final Product product;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final out = onAdd == null;
    final pct = product.discountPercent;

    // Local file → cloud imageUrl → placeholder (see ProductImage).
    final Widget image = ProductImage(product: product);

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
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      onPressed: AuthService.isStaff ? null : onDiscount,
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
                      onPressed:
                          !AuthService.isStaff && hasItems ? onDebt : null,
                      icon: const Icon(Icons.person_outline, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('เชื่อ', maxLines: 1, softWrap: false),
                      ),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange),
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
    const freq = 3500; // supermarket scanner ~3500Hz
    const durationMs = 80;
    const numSamples = sampleRate * durationMs ~/ 1000;
    const dataSize = numSamples * 2;

    final buf = ByteData(44 + dataSize);
    for (final e in [
      [0, 0x52],
      [1, 0x49],
      [2, 0x46],
      [3, 0x46],
      [8, 0x57],
      [9, 0x41],
      [10, 0x56],
      [11, 0x45],
      [12, 0x66],
      [13, 0x6D],
      [14, 0x74],
      [15, 0x20],
      [36, 0x64],
      [37, 0x61],
      [38, 0x74],
      [39, 0x61],
    ]) {
      buf.setUint8(e[0], e[1]);
    }
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
      final s = (sin(2 * pi * freq * i / sampleRate) * 0.65 * env * 32767)
          .round()
          .clamp(-32768, 32767);
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
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nav bar row
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'สแกนบาร์โค้ด',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _bannerSuccess
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black38,
                                      blurRadius: 16,
                                      offset: Offset(0, 4)),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _bannerSuccess
                                        ? Icons.check_circle
                                        : Icons.error_outline,
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
            bottom: 72,
            left: 0,
            right: 0,
            child: Column(children: [
              const Text(
                'จ่อกล้องที่บาร์โค้ดในกรอบ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'ระบบสแกนอัตโนมัติ ไม่ต้องกดปุ่ม',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
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
        Path()
          ..addRRect(
              RRect.fromRectAndRadius(scanRect, const Radius.circular(12))),
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
