import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/table_order.dart';
import '../services/product_service.dart';
import '../services/table_service.dart';
import '../utils/money_format.dart';
import '../utils/operation_error.dart';
import '../utils/stock_quantity.dart';
import 'modifier_picker_sheet.dart';
import 'sale_product_grid.dart';
import 'stock_quantity_dialog.dart';

Future<void> showTableProductPicker(BuildContext context,
        {required String orderId}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => TableProductPicker(
        save: (items, requestId) =>
            TableService.addItems(orderId, items, requestId: requestId),
      ),
    );

/// A local draft keeps the catalog open between selections. Nothing is sent
/// to the table (or kitchen) until the cashier confirms the complete batch.
class TableProductPicker extends StatefulWidget {
  const TableProductPicker(
      {super.key, required this.save, this.products, this.chooseModifiers});

  final Future<void> Function(List<TableOrderItem>, String requestId) save;
  final Stream<List<Product>>? products;
  final Future<ModifierPick?> Function(BuildContext, Product)? chooseModifiers;

  @override
  State<TableProductPicker> createState() => _TableProductPickerState();
}

class _TableProductPickerState extends State<TableProductPicker> {
  late final _products = widget.products ?? ProductService.watchAll();
  final _requestId = const Uuid().v4();
  final _search = TextEditingController();
  List<TableOrderItem> _draft = [];
  List<TableOrderItem>? _submission;
  String _category = 'ทั้งหมด';
  bool _review = false;
  bool _saving = false;
  bool _configuring = false;
  String? _error;

  // Once submitted, retries must contain the exact same batch and key.
  bool get _locked => _saving || _configuring || _submission != null;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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

  Future<void> _editQuantity(int index) async {
    if (_locked) return;
    setState(() => _configuring = true);
    try {
      final item = _draft[index];
      final quantity = await showStockQuantity(context,
          unit: item.unit, weighed: item.isWeighed, initial: item.quantity);
      if (quantity != null && mounted) {
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
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || _configuring || _draft.isEmpty) return;
    FocusScope.of(context).unfocus();
    _submission ??= List.unmodifiable(_draft);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget
          .save(_submission!, _requestId)
          .timeout(const Duration(seconds: 25));
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
          const SnackBar(content: Text('เพิ่มรายการรอส่งครัวแล้ว')));
    } catch (error) {
      if (mounted) setState(() => _error = operationError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _draft.fold<double>(0, (sum, item) => sum + item.subtotal);
    return PopScope(
      canPop: !_saving && !_configuring && _draft.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: FractionallySizedBox(
        heightFactor: .95,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: Column(children: [
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(children: [
                    Expanded(
                        child: Text('เพิ่มสินค้าลงโต๊ะ',
                            style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                        tooltip: 'ปิด',
                        onPressed: _saving || _configuring ? null : _close,
                        icon: const Icon(Icons.close)),
                  ]),
                ),
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    ChoiceChip(
                        label: const Text('เลือกสินค้า'),
                        selected: !_review,
                        onSelected: (_) => setState(() => _review = false)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                        label: Text('รายการที่เลือก (${_draft.length})'),
                        selected: _review,
                        onSelected: (_) {
                          FocusScope.of(context).unfocus();
                          setState(() => _review = true);
                        }),
                  ]),
                ),
              Expanded(
                  child: IndexedStack(
                index: _review
                    ? 1
                    : _error != null
                        ? 2
                        : 0,
                children: [
                  _catalog(),
                  _basket(),
                  SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Text(_error ?? '',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        const Text(
                            'ลองบันทึกซ้ำได้ ระบบจะไม่เพิ่มรายการชุดนี้ซ้ำ'),
                      ])),
                ],
              )),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: _saving || _configuring || _draft.isEmpty
                            ? null
                            : _save,
                        child: Text(_saving
                            ? 'กำลังเพิ่มลงโต๊ะ…'
                            : '${_submission == null ? 'เพิ่มลงโต๊ะ' : 'ลองบันทึกอีกครั้ง'} · ${formatBaht(total)}'),
                      ),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _catalog() => CustomScrollView(
          key: const PageStorageKey('table-product-catalog'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                    hintText: 'ค้นหาสินค้า…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            )),
            StreamBuilder<List<Product>>(
              stream: _products,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(operationError(snapshot.error!))));
                }
                if (!snapshot.hasData) {
                  return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()));
                }
                final all = snapshot.data!;
                final categories =
                    {'ทั้งหมด', ...all.map((p) => p.category)}.toList();
                final category =
                    categories.contains(_category) ? _category : 'ทั้งหมด';
                final query = _search.text.trim().toLowerCase();
                final filtered = all
                    .where((p) =>
                        (category == 'ทั้งหมด' || p.category == category) &&
                        (p.name.toLowerCase().contains(query) ||
                            p.barcode.toLowerCase().contains(query)))
                    .toList();
                return SliverMainAxisGroup(slivers: [
                  SliverToBoxAdapter(
                      child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                        children: categories
                            .map((c) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                      label: Text(c),
                                      selected: c == category,
                                      onSelected: (_) =>
                                          setState(() => _category = c)),
                                ))
                            .toList()),
                  )),
                  if (filtered.isEmpty)
                    const SliverToBoxAdapter(
                        child: Center(child: Text('ไม่พบสินค้า')))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.all(12),
                      sliver:
                          SliverLayoutBuilder(builder: (context, constraints) {
                        final available = constraints.crossAxisExtent;
                        final columns = available < 276
                            ? 1
                            : math.max(2, ((available + 12) / 212).ceil());
                        final width =
                            (available - (columns - 1) * 12) / columns;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisExtent: width * .78 +
                                MediaQuery.textScalerOf(context).scale(66) +
                                76,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          delegate: SliverChildBuilderDelegate((_, index) {
                            final product = filtered[index];
                            final quantity = _draft
                                .where((i) => i.productId == product.id)
                                .fold<num>(0, (sum, i) => sum + i.quantity);
                            return SaleProductCard(
                              key: ValueKey('pick-${product.id}'),
                              product: product,
                              unavailableLabel: quantity > 0
                                  ? 'เลือก ${stockText(quantity)} ${product.unit}'
                                  : null,
                              onTap: _locked ? null : () => _pick(product),
                              footer: SizedBox(
                                  height: 48,
                                  child: TextButton(
                                    onPressed: _locked
                                        ? null
                                        : () => _pick(product, customize: true),
                                    child: const Text('ตัวเลือก / หมายเหตุ',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  )),
                            );
                          }, childCount: filtered.length),
                        );
                      }),
                    ),
                ]);
              },
            ),
          ]);

  Widget _basket() => _draft.isEmpty
      ? const Center(child: Text('ยังไม่ได้เลือกสินค้า'))
      : ListView.builder(
          itemCount: _draft.length,
          itemBuilder: (context, index) {
            final item = _draft[index];
            return ListTile(
              title: Text(item.productName),
              subtitle: Text([
                '${stockText(item.quantity)} ${item.unit} × ${formatBaht(item.unitPrice)} = ${formatBaht(item.subtotal)}',
                ...item.modifiers.map((m) => m.optionName),
                if (item.notes?.isNotEmpty == true) item.notes!,
                'แตะเพื่อแก้จำนวน',
              ].join('\n')),
              onTap: _locked ? null : () => _editQuantity(index),
              trailing: IconButton(
                  tooltip: 'นำรายการออก',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _locked
                      ? null
                      : () => setState(() => _draft.removeAt(index))),
            );
          },
        );
}
