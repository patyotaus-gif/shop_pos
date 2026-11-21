import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/table_order.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/sale_display_service.dart';
import '../services/table_service.dart';
import '../utils/money_format.dart';
import '../utils/operation_error.dart';
import '../utils/stock_quantity.dart';
import 'cart_item_tile.dart';
import 'modifier_picker_sheet.dart';
import 'pos_basket.dart';
import 'pos_catalog.dart';
import 'pos_checkout_panel.dart';
import 'pos_sales_workspace.dart';
import 'sale_display_controls.dart';
import 'stock_quantity_dialog.dart';

Future<void> showTableProductPicker(
  BuildContext context, {
  required String orderId,
  String? tableName,
  ValueListenable<TableOrder>? order,
  Future<void> Function(List<TableOrderItem>, String)? save,
  Future<void> Function(BuildContext)? checkout,
}) =>
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => SaleDisplayScope(
        controller: SaleDisplayService.forShop(AuthService.shopId),
        child: TableProductPicker(
            tableName: tableName,
            order: order,
            checkout: checkout,
            save: save ??
                (items, requestId) => TableService.addItems(orderId, items,
                    requestId: requestId)),
      ),
    ));

/// The takeaway sales workspace with a local draft attached to an existing tab.
/// Saving a batch is idempotent; checkout waits for the refreshed table order.
class TableProductPicker extends StatefulWidget {
  const TableProductPicker(
      {super.key,
      required this.save,
      this.products,
      this.chooseModifiers,
      this.tableName,
      this.order,
      this.checkout});
  final String? tableName;
  final Future<void> Function(List<TableOrderItem>, String requestId) save;
  final Stream<List<Product>>? products;
  final Future<ModifierPick?> Function(BuildContext, Product)? chooseModifiers;
  final ValueListenable<TableOrder>? order;
  final Future<void> Function(BuildContext)? checkout;
  @override
  State<TableProductPicker> createState() => _TableProductPickerState();
}

class _TableProductPickerState extends State<TableProductPicker> {
  String _requestId = const Uuid().v4();
  List<TableOrderItem> _draft = [];
  List<TableOrderItem>? _submission;
  TableOrder? _orderBeforeSubmission;
  bool _saving = false;
  bool _configuring = false;
  String? _error;
  bool get _locked => _saving || _configuring || _submission != null;

  Future<void> _pick(Product product, {bool customize = false}) async {
    if (_locked) return;
    setState(() => _configuring = true);
    try {
      final quantity = product.isWeighed
          ? await showStockQuantity(context, unit: product.unit, weighed: true)
          : 1;
      if (quantity == null || !mounted) return;
      ModifierPick pick = (modifiers: [], notes: null);
      if (customize || product.modifierGroupIds.isNotEmpty) {
        final selected =
            await (widget.chooseModifiers?.call(context, product) ??
                showModifierPicker(context, product: product));
        if (selected == null || !mounted) return;
        pick = selected;
      }
      final item = TableService.itemFromProduct(product,
          quantity: quantity, modifiers: pick.modifiers, notes: pick.notes);
      setState(() => _draft = TableService.appendPending(_draft, item));
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  void _quantity(int index, num value) {
    if (_locked) return;
    final item = _draft[index];
    if (value <= 0) {
      setState(() => _draft.removeAt(index));
    } else if (validStockQuantity(value, weight: item.isWeighed)) {
      setState(() => _draft[index] = item.copyWith(quantity: value));
    }
  }

  Future<void> _editQuantity(String itemId) async {
    if (_locked) return;
    final item = _draft.firstWhere((i) => i.id == itemId);
    setState(() => _configuring = true);
    try {
      final quantity = await showStockQuantity(context,
          unit: item.unit, weighed: item.isWeighed, initial: item.quantity);
      if (!mounted || quantity == null) return;
      final index = _draft.indexWhere((i) => i.id == itemId);
      if (index >= 0) {
        setState(() => _draft[index] = item.copyWith(quantity: quantity));
      }
    } finally {
      if (mounted) setState(() => _configuring = false);
    }
  }

  Future<void> _close() async {
    if (_saving || _configuring) return;
    if (_draft.isNotEmpty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('ออกจากการเลือกสินค้า?'),
                content: Text(_submission == null
                    ? 'รายการที่เลือกไว้ยังไม่ได้เพิ่มลงโต๊ะ'
                    : 'ยังยืนยันผลการบันทึกไม่ได้ กรุณาตรวจรายการบนโต๊ะก่อนเพิ่มซ้ำ'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('เลือกสินค้าต่อ')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('ออกจากหน้านี้')),
                ],
              ));
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save({bool checkout = false}) async {
    if (_saving || _configuring || (!checkout && _draft.isEmpty)) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_draft.isNotEmpty) {
        if (_submission == null) {
          _orderBeforeSubmission = widget.order?.value;
          _submission = List.unmodifiable(_draft);
        }
        // The caller refreshes its confirmed order before acknowledging success.
        await widget
            .save(_submission!, _requestId)
            .timeout(const Duration(seconds: 25));
        if (!mounted) return;
        setState(() {
          _draft = [];
          _submission = null;
          _orderBeforeSubmission = null;
          _requestId = const Uuid().v4();
        });
      }
      if (!mounted) return;
      if (checkout && widget.checkout != null) {
        await widget.checkout!(context);
      } else {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
            const SnackBar(content: Text('เพิ่มรายการรอส่งครัวแล้ว')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = operationError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving && !_configuring && _draft.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.tableName == null
                  ? 'ขายที่โต๊ะ'
                  : 'ขายที่โต๊ะ ${widget.tableName}'),
              leading: IconButton(
                  key: const ValueKey('table-catalog-back'),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const BackButtonIcon(),
                  onPressed: _saving || _configuring ? null : _close)),
          body: SafeArea(
              top: false,
              child: widget.order == null
                  ? _workspace(null)
                  : ValueListenableBuilder<TableOrder>(
                      valueListenable: widget.order!,
                      builder: (_, order, __) => _workspace(order))),
        ),
      );

  Widget _workspace(TableOrder? order) {
    // A live snapshot may already include a batch whose response was lost.
    // Keep the displayed baseline stable until that same batch is acknowledged.
    if (_submission != null) order = _orderBeforeSubmission;
    final existing = order?.items ?? const <TableOrderItem>[];
    final items = [...existing, ..._draft];
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.subtotal);
    final canPay = widget.checkout != null;
    return LayoutBuilder(
        builder: (context, constraints) => PosSalesWorkspace(
              itemCount: items.fold<num>(0, (sum, item) => sum + item.quantity),
              total: subtotal,
              catalog: AbsorbPointer(
                  absorbing: _locked,
                  child: PosCatalog(
                    loadProducts: widget.products == null
                        ? ProductService.watchAll
                        : () => widget.products!,
                    onAdd: _pick, onCustomize: (p) => _pick(p, customize: true),
                    // Preserve table ordering's pending-item behavior; the existing
                    // kitchen/checkout service remains responsible for stock validation.
                    enforceStockAvailability: false,
                  )),
              basket: PosBasket(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    if (index < existing.length) {
                      return Card(
                          child: ListTile(
                              title: Text(item.productName),
                              subtitle: Text([
                                'บนโต๊ะแล้ว · ${item.quantity} ${item.unit}',
                                ...item.modifiers.map((m) => m.optionName),
                                if (item.notes?.isNotEmpty == true) item.notes!
                              ].join('\n')),
                              trailing: Text(formatBaht(item.subtotal))));
                    }
                    final draftIndex = index - existing.length;
                    return AbsorbPointer(
                        absorbing: _locked,
                        child: CartItemTile(
                            item: CartItem(
                                product: Product(
                                    id: item.productId,
                                    name: item.productName,
                                    barcode: '',
                                    price: item.price,
                                    stock: 0,
                                    unit: item.unit,
                                    isWeighed: item.isWeighed),
                                quantity: item.quantity,
                                modifiers: item.modifiers,
                                notes: item.notes),
                            onRemove: () => _quantity(draftIndex, 0),
                            onEditQuantity: () => _editQuantity(item.id),
                            onQtyChanged: (quantity) =>
                                _quantity(draftIndex, quantity)));
                  }),
              checkout: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_saving && (ModalRoute.of(context)?.isCurrent ?? true))
                  const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                if (_submission != null && !_saving)
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                          'ลองบันทึกซ้ำได้ ระบบจะไม่เพิ่มรายการชุดนี้ซ้ำ')),
                if (canPay && _draft.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                              onPressed: _saving || _configuring
                                  ? null
                                  : () => _save(),
                              child: Text(_submission == null
                                  ? 'เพิ่มลงโต๊ะ'
                                  : 'ลองบันทึกอีกครั้ง')))),
                PosCheckoutPanel(
                    subtotal: subtotal,
                    discount: 0,
                    total: subtotal,
                    amountLabel: 'ยอดสินค้า',
                    checkoutLabel: canPay
                        ? 'ชำระเงิน'
                        : (_saving
                            ? 'กำลังเพิ่มลงโต๊ะ…'
                            : '${_submission == null ? 'เพิ่มลงโต๊ะ' : 'ลองบันทึกอีกครั้ง'} · ${formatBaht(subtotal)}'),
                    compact: constraints.maxWidth < 900,
                    horizontalTotal: constraints.maxHeight < 300,
                    hasItems: items.isNotEmpty && !_saving && !_configuring,
                    canDiscount: false,
                    canDebt: false,
                    onCheckout: () => _save(checkout: canPay),
                    onDiscount: () {},
                    onDebt: () {}),
              ]),
            ));
  }
}
