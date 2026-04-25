import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../utils/barcode_lookup.dart';

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
  late final TextEditingController _stock;
  late final TextEditingController _lowStock;
  late String _category;
  bool _scanning = false;
  bool _lookingUp = false;
  bool _saving = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? widget.initialBarcode ?? '');
    _price = TextEditingController(text: p?.price.toStringAsFixed(2) ?? '');
    _stock = TextEditingController(text: p?.stock.toString() ?? '0');
    _lowStock = TextEditingController(text: p?.lowStockThreshold.toString() ?? '5');
    _category = p?.category ?? 'ทั่วไป';

    if (_barcode.text.isNotEmpty && !_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupBarcode());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _stock.dispose();
    _lowStock.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode() async {
    if (_barcode.text.isEmpty) return;
    setState(() => _lookingUp = true);
    final result = await BarcodeLookup.lookup(_barcode.text);
    setState(() => _lookingUp = false);
    if (result != null && _name.text.isEmpty) {
      setState(() => _name.text = result['name'] ?? '');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ดึงชื่อสินค้าสำเร็จ')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final product = Product(
        id: widget.product?.id ?? '',
        name: _name.text.trim(),
        barcode: _barcode.text.trim(),
        price: double.parse(_price.text),
        stock: int.parse(_stock.text),
        lowStockThreshold: int.parse(_lowStock.text),
        category: _category,
      );

      if (_isEdit) {
        await ProductService.update(product);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
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
                        icon: const Icon(Icons.qr_code_scanner),
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
                    validator: (v) => v!.trim().isEmpty ? 'กรุณากรอกชื่อสินค้า' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'หมวดหมู่',
                      border: OutlineInputBorder(),
                    ),
                    items: ProductService.categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ราคา (บาท) *',
                      prefixText: '฿',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v!.isEmpty) return 'กรุณากรอกราคา';
                      if (double.tryParse(v) == null) return 'ราคาไม่ถูกต้อง';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'จำนวนสต็อก *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v!.isEmpty) return 'กรุณากรอกสต็อก';
                            if (int.tryParse(v) == null) return 'ไม่ถูกต้อง';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _lowStock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'แจ้งเตือนเมื่อเหลือ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
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
