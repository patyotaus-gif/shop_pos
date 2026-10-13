import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/unit_cost_calculator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/ingredient.dart';
import '../models/modifier_group.dart';
import '../models/product.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/image_service.dart';
import '../services/ingredient_service.dart';
import '../services/modifier_service.dart';
import 'modifier_groups_screen.dart';
import '../services/product_service.dart';
import '../services/shop_service.dart';
import '../utils/barcode_lookup.dart';
import '../widgets/upgrade_prompt.dart';
import '../widgets/product_category_field.dart';
import '../utils/stock_quantity.dart';
import 'product_inventory_screen.dart';

class ProductFormScreen extends StatefulWidget {
  final Product? product;
  final String? initialBarcode;

  const ProductFormScreen({super.key, this.product, this.initialBarcode});

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stock;
  late final TextEditingController _lowStock;
  late String _category;
  late final String _productId;
  late final Map<String, TextEditingController> _inventory;
  bool _weighed = false, _trackLots = false;
  late final Stream<List<Product>> _products;
  bool _scanning = false;
  bool _lookingUp = false;
  bool _saving = false;
  bool _isPinned = false;
  File? _imageFile;
  bool _removeBackground = false;
  late Set<String> _modifierGroupIds;
  late String _stockMode;
  late List<RecipeLine> _recipe;
  List<Ingredient>? _ingredients; // loaded when the recipe editor shows

  bool get _isEdit => widget.product != null;

  Widget _inventoryFields() => ExpansionTile(
        initiallyExpanded: true,
        title: const Text('รหัส หน่วย และการจัดการสต๊อก'),
        children: [
          for (final field in const {
            'sku': 'SKU (เว้นว่างให้สร้างอัตโนมัติ)',
            'unit': 'หน่วยขาย เช่น ชิ้น / กก.',
            'packUnit': 'ชื่อหน่วยรับเข้า เช่น ลัง',
            'packSize': '1 แพ็ก/ลัง มีกี่หน่วยขาย',
            'supplier': 'ผู้จำหน่าย (ถ้ามี)',
            'location': 'ตำแหน่งจัดเก็บ (ถ้ามี)',
            'notes': 'หมายเหตุสินค้า'
          }.entries)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _inventory[field.key],
                  maxLength: field.key == 'notes' ? 300 : 64,
                  keyboardType: field.key == 'packSize'
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                      labelText: field.value,
                      counterText: '',
                      border: const OutlineInputBorder()),
                )),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ขายแบบชั่งน้ำหนัก'),
              subtitle: const Text(
                  'ราคาต่อ 1 หน่วยขาย เช่น บาท/กก. ระบุจำนวนได้ 3 ตำแหน่ง'),
              value: _weighed,
              onChanged: (v) => setState(() {
                    _weighed = v;
                    if (!_isEdit && v) _inventory['unit']!.text = 'กก.';
                  })),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ติดตามล็อตและวันหมดอายุ'),
              subtitle:
                  const Text('ตัดล็อตที่หมดอายุก่อน ไม่นำล็อตหมดอายุไปขาย'),
              value: _trackLots,
              onChanged: (v) => setState(() => _trackLots = v)),
          if (_trackLots && widget.product?.trackLots != true) ...[
            TextFormField(
                controller: _inventory['lot'],
                decoration: const InputDecoration(
                    labelText: 'ล็อตของสต๊อกเริ่มต้น (เมื่อมีสต๊อก)')),
            TextFormField(
                controller: _inventory['expiry'],
                decoration: const InputDecoration(
                    labelText: 'วันหมดอายุของล็อตเริ่มต้น',
                    hintText: 'YYYY-MM-DD เช่น 2027-01-31')),
            const SizedBox(height: 16),
          ],
        ],
      );

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _productId = p?.id ?? ProductService.newId();
    _weighed = p?.isWeighed ?? false;
    _trackLots = p?.trackLots ?? false;
    _inventory = {
      'sku': TextEditingController(text: p?.sku ?? ''),
      'unit': TextEditingController(text: p?.unit ?? 'ชิ้น'),
      'packUnit': TextEditingController(text: p?.packUnit ?? 'แพ็ก'),
      'packSize': TextEditingController(text: '${p?.unitsPerPack ?? 1}'),
      'supplier': TextEditingController(text: p?.supplierName ?? ''),
      'location': TextEditingController(text: p?.storageLocation ?? ''),
      'notes': TextEditingController(text: p?.notes ?? ''),
      'lot': TextEditingController(),
      'expiry': TextEditingController(),
    };
    _name = TextEditingController(text: p?.name ?? '');
    _barcode =
        TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _price = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '');
    _costPrice = TextEditingController(
        text: p?.costPrice != null && p!.costPrice > 0
            ? p.costPrice.toStringAsFixed(2)
            : '');
    _stock = TextEditingController(text: p?.stock.toString() ?? '0');
    _lowStock =
        TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    _category = p?.category ?? 'ทั่วไป';
    _products = ProductService.watchAll();
    _isPinned = p?.isPinned ?? false;
    _modifierGroupIds = {...(p?.modifierGroupIds ?? const <String>[])};
    _stockMode = p?.stockMode ?? 'count';
    _recipe = [...(p?.recipe ?? const <RecipeLine>[])];
    if (p?.imagePath != null) _imageFile = File(p!.imagePath!);

    if (_barcode.text.isNotEmpty && !_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupBarcode());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _costPrice.dispose();
    _stock.dispose();
    _lowStock.dispose();
    for (final c in _inventory.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    setState(() => _imageFile = File(picked.path));
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายรูป'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากคลังรูป'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_imageFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('ลบรูป', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _imageFile = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookupBarcode() async {
    if (_barcode.text.isEmpty) return;
    setState(() => _lookingUp = true);
    final result = await BarcodeLookup.lookup(_barcode.text);
    setState(() => _lookingUp = false);
    if (!mounted) return;
    if (result != null && _name.text.isEmpty) {
      setState(() => _name.text = result['name'] ?? '');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ดึงชื่อสินค้าสำเร็จ')),
      );
    }
  }

  void _loadIngredientsOnce() {
    if (_ingredients != null) return;
    IngredientService.getAll().then((list) {
      if (mounted) setState(() => _ingredients = list);
    });
  }

  double get _recipeCost {
    final costById = {
      for (final i in _ingredients ?? const <Ingredient>[]) i.id: i.avgCost
    };
    return _recipe.fold(
        0, (s, l) => s + (costById[l.ingredientId] ?? 0) * l.qty);
  }

  Widget _buildRecipeSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ingredients = _ingredients ?? const <Ingredient>[];
    final byId = {for (final i in ingredients) i.id: i};
    if (_stockMode == 'recipe') _loadIngredientsOnce();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'count', label: Text('นับสต็อกเอง')),
            ButtonSegment(value: 'recipe', label: Text('ใช้สูตรวัตถุดิบ')),
          ],
          selected: {_stockMode},
          onSelectionChanged: (s) {
            if (s.first == 'recipe' && (_weighed || _trackLots)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'ปิดการชั่งน้ำหนักและติดตามล็อตก่อนเปลี่ยนไปใช้สูตร วัตถุดิบจัดการแยกจากสินค้า'),
              ));
              return;
            }
            setState(() => _stockMode = s.first);
          },
        ),
        const SizedBox(height: 8),
        if (_stockMode == 'recipe') ...[
          Text(
            'ขาย 1 จาน = ตัดวัตถุดิบตามสูตรอัตโนมัติ · ต้นทุนคิดจากสูตร',
            style: TextStyle(
                fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _recipe.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                  byId[_recipe[i].ingredientId]?.name ??
                      '(วัตถุดิบถูกลบ — แตะถังขยะเพื่อเอาออก)',
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                  '${_recipe[i].qty} ${byId[_recipe[i].ingredientId]?.unit ?? ''}'
                  ' · ฿${((byId[_recipe[i].ingredientId]?.avgCost ?? 0) * _recipe[i].qty).toStringAsFixed(2)}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editRecipeLine(index: i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: Colors.red),
                    onPressed: () => setState(() => _recipe.removeAt(i)),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('เพิ่มวัตถุดิบในสูตร'),
                onPressed: ingredients.isEmpty && _ingredients != null
                    ? null
                    : () => _editRecipeLine(),
              ),
              const Spacer(),
              Text('ต้นทุนสูตร ฿${_recipeCost.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cs.primary)),
            ],
          ),
          if (_ingredients != null && ingredients.isEmpty)
            Text('ยังไม่มีวัตถุดิบ — เพิ่มได้ที่หน้า สินค้า → "วัตถุดิบ"',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _editRecipeLine({int? index}) async {
    _loadIngredientsOnce();
    final ingredients = _ingredients ?? const <Ingredient>[];
    if (ingredients.isEmpty) return;
    final existing = index != null ? _recipe[index] : null;
    String selectedId = existing?.ingredientId ?? ingredients.first.id;
    final qtyCtrl =
        TextEditingController(text: existing != null ? '${existing.qty}' : '');

    final line = await showDialog<RecipeLine>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(index == null ? 'เพิ่มวัตถุดิบในสูตร' : 'แก้ไขสูตร'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedId,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: 'วัตถุดิบ', border: OutlineInputBorder()),
                items: [
                  for (final i in ingredients)
                    DropdownMenuItem(
                        value: i.id, child: Text('${i.name} (${i.unit})')),
                ],
                onChanged: (v) => setDlg(() => selectedId = v ?? selectedId),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'จำนวนต่อ 1 จาน', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qtyCtrl.text.trim());
                if (q == null || q <= 0) return;
                Navigator.pop(
                    ctx, RecipeLine(ingredientId: selectedId, qty: q));
              },
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );
    if (line == null) return;
    setState(() {
      if (index != null) {
        _recipe[index] = line;
      } else {
        _recipe.add(line);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final tempId = widget.product?.id.isNotEmpty == true
          ? widget.product!.id
          : DateTime.now().millisecondsSinceEpoch.toString();
      final shopId = (await ProductService.currentShopId()) ?? tempId;

      String? savedImagePath = widget.product?.imagePath;
      String? savedImageUrl = widget.product?.imageUrl;

      if (_imageFile != null) {
        File toSave = _imageFile!;
        if (_removeBackground) {
          toSave = await ImageService.removeBackground(toSave);
        }
        final result = await ImageService.saveProduct(toSave, shopId, tempId);
        savedImagePath = result.localPath;
        savedImageUrl = result.imageUrl;
      }

      final isRecipe = _stockMode == 'recipe';
      // Recipe mode: cost comes from the recipe (Σ qty × avgCost) so profit
      // reports reflect real ingredient costs automatically.
      double costPrice = double.tryParse(_costPrice.text) ?? 0;
      final originalCost = widget.product?.costPrice;
      if (originalCost != null &&
          _costPrice.text.trim() ==
              (originalCost > 0 ? originalCost.toStringAsFixed(2) : '')) {
        costPrice =
            originalCost; // Preserve receipt-weighted average precision unless edited.
      }
      if (isRecipe && _ingredients != null) {
        final costById = {for (final i in _ingredients!) i.id: i.avgCost};
        costPrice = _recipe.fold(
            0, (s, l) => s + (costById[l.ingredientId] ?? 0) * l.qty);
      }

      final product = Product(
        id: _productId,
        sku: _inventory['sku']!.text,
        unit: _inventory['unit']!.text,
        packUnit: _inventory['packUnit']!.text,
        unitsPerPack: num.tryParse(_inventory['packSize']!.text) ?? 0,
        supplierName: _inventory['supplier']!.text.trim(),
        storageLocation: _inventory['location']!.text.trim(),
        notes: _inventory['notes']!.text.trim(),
        isWeighed: _weighed,
        trackLots: _trackLots,
        stockLots: widget.product?.trackLots == true
            ? widget.product!.stockLots
            : (_trackLots && (num.tryParse(_stock.text) ?? 0) > 0
                ? [
                    {
                      'id': 'opening',
                      'number': _inventory['lot']!.text.trim(),
                      'expiresOn': _inventory['expiry']!.text.trim(),
                      'quantity': num.parse(_stock.text),
                    }
                  ]
                : []),
        name: _name.text.trim(),
        barcode: _barcode.text.trim(),
        price: double.parse(_price.text),
        costPrice: costPrice,
        // Recipe mode ignores the product's own counter — keep whatever was
        // there so switching back to count mode doesn't lose the number.
        stock: isRecipe ? (widget.product?.stock ?? 0) : num.parse(_stock.text),
        lowStockThreshold: isRecipe
            ? (widget.product?.lowStockThreshold ?? 5)
            : num.parse(_lowStock.text),
        category: _category,
        isPinned: _isPinned,
        imagePath: savedImagePath,
        imageUrl: savedImageUrl,
        salePrice: widget.product?.salePrice,
        saleUntil: widget.product?.saleUntil,
        modifierGroupIds: _modifierGroupIds.toList(),
        stockMode: _stockMode,
        recipe: isRecipe ? _recipe : const [],
      );

      if (_isEdit) {
        await ProductService.update(product, original: widget.product);
      } else {
        await ProductService.add(product);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบสินค้า'),
        content: Text('ต้องการลบ "${widget.product!.name}" ใช่ไหม?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ProductService.delete(widget.product!.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'แก้ไขสินค้า' : 'เพิ่มสินค้า'),
        centerTitle: true,
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _delete,
            ),
        ],
      ),
      body: _scanning
          ? SizedBox(
              height: 300,
              child: MobileScanner(
                onDetect: (capture) {
                  final code = capture.barcodes.firstOrNull?.rawValue;
                  if (code != null) {
                    setState(() {
                      _barcode.text = code;
                      _scanning = false;
                    });
                    _lookupBarcode();
                  }
                },
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // รูปสินค้า
                  GestureDetector(
                    onTap: _showImageSourceSheet,
                    child: Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child:
                                  Image.file(_imageFile!, fit: BoxFit.contain),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 40, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('เพิ่มรูปสินค้า',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                    ),
                  ),
                  if (_imageFile != null) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      value: _removeBackground,
                      onChanged: (v) => setState(() => _removeBackground = v),
                      title: const Text('ตัดพื้นหลังออก'),
                      subtitle: const Text('เหมาะกับรูปที่มีพื้นหลังสีเรียบ'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Barcode
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _barcode,
                          decoration: InputDecoration(
                            labelText: 'Barcode',
                            border: const OutlineInputBorder(),
                            suffixIcon: _lookingUp
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _lookupBarcode,
                                  ),
                          ),
                          onEditingComplete: _lookupBarcode,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: const Icon(Icons.barcode_reader),
                        tooltip: 'สแกนบาร์โค้ด',
                        onPressed: () => setState(() => _scanning = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อสินค้า *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v!.trim().isEmpty ? 'กรุณากรอกชื่อสินค้า' : null,
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<List<Product>>(
                    stream: _products,
                    builder: (context, snapshot) => ProductCategoryField(
                      initialValue: _category,
                      categories: ProductService.categoriesFor(
                          snapshot.data ?? const []),
                      onChanged: (value) => _category = value,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ราคาขาย *',
                            prefixText: '฿',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v!.isEmpty) return 'กรุณากรอกราคา';
                            if (double.tryParse(v) == null) {
                              return 'ราคาไม่ถูกต้อง';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _costPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ราคาต้นทุน',
                            prefixText: '฿',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_stockMode != 'recipe')
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('ช่วยคำนวณต้นทุนต่อหน่วย'),
                            onPressed: () async {
                              final cost =
                                  await showUnitCostCalculator(context);
                              if (cost != null && mounted) {
                                setState(() =>
                                    _costPrice.text = cost.toStringAsFixed(2));
                              }
                            })),
                  const SizedBox(height: 16),
                  // ── โหมดสต็อก + สูตรวัตถุดิบ (Restaurant) ──
                  StreamBuilder<Shop?>(
                    stream: ShopService.watchCurrentShop(),
                    builder: (context, snap) {
                      if (snap.data == null ||
                          !Entitlements.canUseRecipes(
                              snap.data!.tier, snap.data!.shopType)) {
                        return const SizedBox.shrink();
                      }
                      return _buildRecipeSection(context);
                    },
                  ),
                  if (_stockMode == 'count') _inventoryFields(),
                  if (_stockMode == 'count')
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _stock,
                            readOnly: _isEdit,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: _isEdit
                                  ? 'สต๊อกขณะเปิดหน้า'
                                  : 'สต๊อกเริ่มต้น *',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if (v!.isEmpty) return 'กรุณากรอกสต็อก';
                              final q = num.tryParse(v);
                              if (q == null ||
                                  !validStockQuantity(q,
                                      weight: _weighed, zero: true)) {
                                return 'ตรวจจำนวน/ทศนิยม';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          // Low-stock threshold is part of inventory
                          // tracking — Solo tier doesn't include that, so
                          // we disable the field and surface the upgrade
                          // ask inline. Tap the lock icon for the modal.
                          child: StreamBuilder<Shop?>(
                            stream: ShopService.watchCurrentShop(),
                            builder: (context, snap) {
                              final tier = snap.data?.tier ?? ShopTier.full;
                              final enabled =
                                  Entitlements.canUseInventory(tier);
                              return TextFormField(
                                controller: _lowStock,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                validator: (value) {
                                  final q = num.tryParse(value ?? '');
                                  return q == null ||
                                          !validStockQuantity(q,
                                              weight: _weighed, zero: true)
                                      ? 'ตรวจจำนวน'
                                      : null;
                                },
                                enabled: enabled,
                                decoration: InputDecoration(
                                  labelText: 'แจ้งเตือนเมื่อเหลือ',
                                  border: const OutlineInputBorder(),
                                  helperText: enabled
                                      ? null
                                      : 'ใช้ได้ในแผน Lite ขึ้นไป',
                                  suffixIcon: enabled
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.lock_outline,
                                              size: 18),
                                          onPressed: () => showUpgradePrompt(
                                            context,
                                            feature:
                                                EntitlementFeature.inventory,
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  if (_isEdit && _stockMode == 'count')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('รับเข้า / ตรวจนับ / ประวัติสต๊อก'),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ProductInventoryScreen(
                                  productId: _productId))),
                    ),
                  SwitchListTile(
                    value: _isPinned,
                    onChanged: (v) => setState(() => _isPinned = v),
                    title: const Text('ปักหมุดในหน้าขาย'),
                    subtitle: const Text('แสดงในปุ่มลัดหน้า POS'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  // Restaurant-only: pick which modifier groups (size,
                  // spice level, add-ons) attach to this product. Hidden
                  // for retail shops where modifiers are irrelevant.
                  StreamBuilder<Shop?>(
                    stream: ShopService.watchCurrentShop(),
                    builder: (context, shopSnap) {
                      if (shopSnap.data?.shopType != ShopType.restaurant) {
                        return const SizedBox.shrink();
                      }
                      return StreamBuilder<List<ModifierGroup>>(
                        stream: ModifierService.watchAll(),
                        builder: (context, groupSnap) {
                          final groups = groupSnap.data ?? const [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('ตัวเลือกเสริม (Add-on)',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary)),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.tune_outlined,
                                        size: 16),
                                    label: const Text('จัดการกลุ่ม'),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const ModifierGroupsScreen()),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'เลือกกลุ่มที่ลูกค้าจะปรับได้ตอนสั่ง เช่น ระดับความเผ็ด/เพิ่มไข่',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.6)),
                              ),
                              const SizedBox(height: 8),
                              if (groups.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'ยังไม่มีกลุ่ม — แตะ "จัดการกลุ่ม" ด้านบนเพื่อสร้าง เช่น "ระดับความเผ็ด"',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7)),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: groups.map((g) {
                                    final sel =
                                        _modifierGroupIds.contains(g.id);
                                    return FilterChip(
                                      label: Text(g.name),
                                      selected: sel,
                                      onSelected: (v) => setState(() {
                                        if (v) {
                                          _modifierGroupIds.add(g.id);
                                        } else {
                                          _modifierGroupIds.remove(g.id);
                                        }
                                      }),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(_isEdit ? 'บันทึก' : 'เพิ่มสินค้า'),
                  ),
                ],
              ),
            ),
    );
  }
}
