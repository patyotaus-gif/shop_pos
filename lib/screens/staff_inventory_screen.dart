import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import '../services/staff_inventory_api.dart';
import '../utils/operation_error.dart';
import '../utils/stock_quantity.dart';

const _actions = {
  'stockReceive': 'รับสินค้าเข้า',
  'stockWaste': 'ตัดของเสีย / ชำรุด',
  'stockCount': 'ตรวจนับ'
};
const _permissions = {
  'stockReceive': 'stockReceive',
  'stockWaste': 'stockWaste',
  'stockCount': 'stock'
};

class StaffInventoryScreen extends StatefulWidget {
  const StaffInventoryScreen({super.key, this.api = const StaffInventoryApi()});
  final StaffInventoryApi api;
  @override
  State<StaffInventoryScreen> createState() => _StaffInventoryScreenState();
}

class _StaffInventoryScreenState extends State<StaffInventoryScreen> {
  final _search = TextEditingController();
  String _mode = 'name', _query = '', _queryMode = 'name';
  String? _cursor, _error;
  final List<Map<String, dynamic>> _rows = [];
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _cursor = null;
        _query = _search.text.trim();
        _queryMode = _mode;
      }
    });
    try {
      final data = await widget.api.call('inventoryProducts', {
        'search': _query,
        'mode': _queryMode,
        if (_cursor != null) 'cursor': _cursor
      });
      if (!mounted) return;
      setState(() {
        _rows.addAll((data['records'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map)));
        _cursor = data['nextCursor'] as String?;
      });
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
        context, MaterialPageRoute(builder: (_) => const _InventoryScanner()));
    if (!mounted || code == null) return;
    setState(() {
      _mode = 'barcode';
      _search.text = code;
    });
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สต๊อกสินค้า'), actions: [
        IconButton(
            tooltip: 'โหลดใหม่',
            onPressed: _busy ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh))
      ]),
      body: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  DropdownButtonFormField<String>(
                      initialValue: _mode,
                      key: ValueKey(_mode),
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'ค้นหาด้วย'),
                      items: const [
                        DropdownMenuItem(
                            value: 'name',
                            child: Text('ชื่อสินค้า (ขึ้นต้นด้วย)')),
                        DropdownMenuItem(
                            value: 'barcode', child: Text('บาร์โค้ด')),
                        DropdownMenuItem(value: 'sku', child: Text('SKU'))
                      ],
                      onChanged:
                          _busy ? null : (v) => setState(() => _mode = v!)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: _search,
                            maxLength: 150,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                labelText: 'ค้นหาสินค้า',
                                counterText: '',
                                suffixIcon: IconButton(
                                    tooltip: 'ค้นหา',
                                    onPressed:
                                        _busy ? null : () => _load(reset: true),
                                    icon: const Icon(Icons.search))),
                            onSubmitted: (_) => _load(reset: true))),
                    IconButton(
                        tooltip: 'สแกนบาร์โค้ด',
                        onPressed: _busy ? null : _scan,
                        icon: const Icon(Icons.barcode_reader))
                  ]),
                ])),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
                child: ListView(children: [
              if (_error != null)
                ListTile(
                    title: Text(_error!),
                    trailing: IconButton(
                        tooltip: 'ลองใหม่',
                        onPressed:
                            _busy ? null : () => _load(reset: _rows.isEmpty),
                        icon: const Icon(Icons.refresh))),
              if (!_busy && _error == null && _rows.isEmpty)
                const ListTile(title: Text('ไม่พบสินค้า')),
              for (final p in _rows)
                ListTile(
                    title: Text('${p['name']}'),
                    subtitle: Text(
                        'คงเหลือ ${stockText(p['stock'] as num)} ${p['unit']} · ราคาขาย ฿${(p['price'] as num).toStringAsFixed(2)}\nบาร์โค้ด: ${p['barcode'] == '' ? '-' : p['barcode']}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => StaffInventoryDetailScreen(
                                  productId: p['id'] as String,
                                  api: widget.api)));
                      if (mounted) await _load(reset: true);
                    }),
              if (_cursor != null)
                TextButton(
                    onPressed: _busy ? null : () => _load(),
                    child: const Text('โหลดสินค้าเพิ่มเติม')),
            ])),
          ])));
}

class _InventoryScanner extends StatefulWidget {
  const _InventoryScanner();
  @override
  State<_InventoryScanner> createState() => _InventoryScannerState();
}

class _InventoryScannerState extends State<_InventoryScanner> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สแกนบาร์โค้ด')),
      body: SafeArea(
          child: MobileScanner(
              errorBuilder: (context, error) => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                          'เปิดกล้องไม่สำเร็จ กรุณาตรวจสิทธิ์กล้อง หรือกลับไปกรอกบาร์โค้ด'))),
              onDetect: (capture) {
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (!_done && value != null && value.trim().isNotEmpty) {
                  _done = true;
                  Navigator.pop(context, value.trim());
                }
              })));
}

class StaffInventoryDetailScreen extends StatefulWidget {
  const StaffInventoryDetailScreen(
      {super.key,
      required this.productId,
      this.api = const StaffInventoryApi()});
  final String productId;
  final StaffInventoryApi api;
  @override
  State<StaffInventoryDetailScreen> createState() =>
      _StaffInventoryDetailScreenState();
}

class _StaffInventoryDetailScreenState
    extends State<StaffInventoryDetailScreen> {
  Map<String, dynamic>? _product;
  String? _error;
  bool _busy = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api
          .call('inventoryProduct', {'productId': widget.productId});
      if (mounted) {
        setState(() {
          _product = Map<String, dynamic>.from(data['record'] as Map);
          _revision++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _adjust(String action) async {
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StaffStockAdjustmentDialog(
            product: _product!, action: action, api: widget.api));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดสต๊อก'), actions: [
          IconButton(
              tooltip: 'โหลดใหม่',
              onPressed: _busy ? null : _load,
              icon: const Icon(Icons.refresh))
        ]),
        body: SafeArea(
            top: false,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null) Text(_error!),
              if (p != null) ...[
                Text('${p['name']}',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                    'SKU: ${p['sku'] == '' ? '-' : p['sku']}\nบาร์โค้ด: ${p['barcode'] == '' ? '-' : p['barcode']}'),
                Text(
                    'ราคาขาย ฿${(p['price'] as num).toStringAsFixed(2)} / ${p['unit']}'),
                if (p.containsKey('unitCost'))
                  Text(
                      'ต้นทุน ฿${(p['unitCost'] as num).toStringAsFixed(2)} / ${p['unit']}'),
                const SizedBox(height: 12),
                Text(
                    'คงเหลือ ${stockText(p['stock'] as num)} ${p['unit']} · จองออนไลน์ ${stockText(p['reserved'] as num)} · พร้อมขาย ${stockText(p['available'] as num)}'),
                const SizedBox(height: 12),
                if (p['stockMode'] == 'recipe')
                  const Text('สินค้านี้ใช้สูตร ให้เจ้าของร้านจัดการที่วัตถุดิบ')
                else
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in _actions.entries)
                      if (widget.api.can(_permissions[e.key]!))
                        OutlinedButton(
                            onPressed: _busy || _error != null
                                ? null
                                : () => _adjust(e.key),
                            child: Text(e.value))
                  ]),
                if (p['trackLots'] == true) ...[
                  const SizedBox(height: 16),
                  Text('ล็อตสินค้า',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final lot in p['stockLots'] as List)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${lot['number']} · ${stockText(lot['quantity'] as num)} ${p['unit']}'),
                        subtitle: Text('หมดอายุ ${lot['expiresOn']}')),
                ],
                if (widget.api.can('stockHistory')) ...[
                  const Divider(height: 32),
                  StaffStockHistory(
                      key: ValueKey(_revision),
                      productId: widget.productId,
                      api: widget.api)
                ],
              ],
            ])));
  }
}

class StaffStockAdjustmentDialog extends StatefulWidget {
  const StaffStockAdjustmentDialog(
      {super.key,
      required this.product,
      required this.action,
      required this.api});
  final Map<String, dynamic> product;
  final String action;
  final StaffInventoryApi api;
  @override
  State<StaffStockAdjustmentDialog> createState() =>
      _StaffStockAdjustmentDialogState();
}

class _StaffStockAdjustmentDialogState
    extends State<StaffStockAdjustmentDialog> {
  final _quantity = TextEditingController(),
      _reason = TextEditingController(),
      _document = TextEditingController(),
      _lotNumber = TextEditingController(),
      _cost = TextEditingController();
  String? _lotId, _expiresOn, _error;
  bool _busy = false, _loading = true;
  Map<String, dynamic>? _pending;
  String get _action => _pending?['action'] as String? ?? widget.action;
  bool get _receive => _action == 'stockReceive';
  bool get _locked => _busy || _pending != null || _loading;
  @override
  void initState() {
    super.initState();
    final lots = widget.product['stockLots'] as List;
    if (widget.action != 'stockReceive' && lots.isNotEmpty) {
      _lotId = lots.first['id'] as String;
    }
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = await widget.api.pending(widget.product['id'] as String);
      if (mounted) {
        setState(() {
          _pending = p;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    }
  }

  @override
  void dispose() {
    for (final c in [_quantity, _reason, _document, _lotNumber, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_pending == null) {
        final quantity = num.tryParse(_quantity.text.trim()),
            cost = num.tryParse(_cost.text.trim());
        if (quantity == null ||
            !quantity.isFinite ||
            quantity < 0 ||
            (_action != 'stockCount' && quantity == 0) ||
            (widget.product['isWeighed'] != true &&
                quantity != quantity.round()) ||
            (quantity * 1000 - (quantity * 1000).round()).abs() > 0.000001 ||
            _reason.text.trim().isEmpty) {
          throw StateError('กรอกจำนวนและเหตุผลให้ถูกต้อง');
        }
        if (_cost.text.trim().isNotEmpty &&
            (cost == null || !cost.isFinite || cost < 0)) {
          throw StateError('ต้นทุนรวมไม่ถูกต้อง');
        }
        if (widget.product['trackLots'] == true &&
            _lotId == null &&
            (!_receive ||
                _lotNumber.text.trim().isEmpty ||
                _expiresOn == null)) {
          throw StateError('เลือกล็อต หรือระบุล็อตใหม่และวันหมดอายุ');
        }
        final request = <String, dynamic>{
          'action': widget.action,
          'productId': widget.product['id'],
          'requestId': const Uuid().v4(),
          'quantity': quantity,
          'expectedRevision': widget.product['stockRevision'],
          'reason': _reason.text.trim(),
          'documentNumber': _document.text.trim(),
          if (_lotId != null) 'lotId': _lotId,
          if (widget.product['trackLots'] == true &&
              _receive &&
              _lotId == null) ...{
            'lotNumber': _lotNumber.text.trim(),
            'expiresOn': _expiresOn
          },
          if (_receive && widget.api.can('cost') && cost != null)
            'totalCost': cost
        };
        await widget.api.savePending(widget.product['id'] as String, request);
        _pending = request;
      }
      await widget.api.call(_pending!['action'] as String,
          Map<String, dynamic>.from(_pending!)..remove('action'));
      await widget.api.clearPending(widget.product['id'] as String);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // These responses confirm that this request was rejected before writing.
      // Transport/timeouts remain pending so a retry reuses the same request ID.
      if (e is FirebaseFunctionsException &&
          [
            'failed-precondition',
            'invalid-argument',
            'permission-denied',
            'unauthenticated',
            'not-found'
          ].contains(e.code) &&
          _pending != null) {
        try {
          await widget.api.clearPending(widget.product['id'] as String);
          _pending = null;
        } catch (_) {/* Keep the pending payload if local persistence fails. */}
      }
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product, lots = p['stockLots'] as List;
    return PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text('${_actions[_action]} · ${p['name']}'),
          content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (_loading && _error == null)
                      const LinearProgressIndicator(),
                    if (_pending != null)
                      Text(
                          'รายการรอยืนยัน: ${_pending!['quantity']} ${p['unit']}\n${_pending!['reason']}\nกดตรวจผล / ลองใหม่เพื่อยืนยันรายการเดิม ไม่เพิ่มรายการซ้ำ'),
                    if (_pending == null) ...[
                      Text(
                          'คงเหลือ ${stockText(p['stock'] as num)} ${p['unit']}'),
                      if (p['trackLots'] == true) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                            initialValue: _lotId ?? '',
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'ล็อตสินค้า'),
                            items: [
                              if (_receive)
                                const DropdownMenuItem(
                                    value: '', child: Text('เพิ่มล็อตใหม่')),
                              if (!_receive && lots.isEmpty)
                                const DropdownMenuItem(
                                    value: '', child: Text('ยังไม่มีล็อต')),
                              for (final l in lots)
                                DropdownMenuItem(
                                    value: l['id'] as String,
                                    child: Text(
                                        '${l['number']} · ${l['expiresOn']}',
                                        overflow: TextOverflow.ellipsis))
                            ],
                            onChanged: _locked
                                ? null
                                : (v) => setState(
                                    () => _lotId = v == '' ? null : v)),
                        if (_receive && _lotId == null) ...[
                          const SizedBox(height: 12),
                          TextField(
                              controller: _lotNumber,
                              enabled: !_locked,
                              maxLength: 100,
                              decoration:
                                  const InputDecoration(labelText: 'เลขล็อต')),
                          TextButton.icon(
                              icon: const Icon(Icons.event),
                              label: Text(_expiresOn ?? 'เลือกวันหมดอายุ'),
                              onPressed: _locked
                                  ? null
                                  : () async {
                                      final date = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100));
                                      if (date != null && mounted) {
                                        setState(() => _expiresOn =
                                            DateFormat('yyyy-MM-dd')
                                                .format(date));
                                      }
                                    }),
                        ],
                      ],
                      const SizedBox(height: 12),
                      TextField(
                          controller: _quantity,
                          enabled: !_locked,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText:
                                  '${_action == 'stockCount' ? 'จำนวนที่นับได้' : _receive ? 'จำนวนรับเข้า' : 'จำนวนตัดออก'} (${p['unit']})',
                              helperText: _action == 'stockCount'
                                  ? 'กรอกยอดคงเหลือจริงของสินค้าหรือล็อตที่เลือก'
                                  : 'กรอกเฉพาะจำนวนที่เพิ่มหรือลด')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _reason,
                          enabled: !_locked,
                          maxLength: 300,
                          decoration: const InputDecoration(
                              labelText: 'เหตุผล',
                              helperText:
                                  'เช่น รับจากผู้จำหน่าย / ชำรุด / หมดอายุ')),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _document,
                          enabled: !_locked,
                          maxLength: 100,
                          decoration: const InputDecoration(
                              labelText: 'เลขเอกสาร (ถ้ามี)')),
                      if (_receive && widget.api.can('cost')) ...[
                        const SizedBox(height: 12),
                        TextField(
                            controller: _cost,
                            enabled: !_locked,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'ต้นทุนรวมที่รับเข้า (บาท)',
                                helperText: 'ไม่กรอก = ใช้ต้นทุนต่อหน่วยเดิม'))
                      ],
                    ],
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('ปิด')),
            FilledButton(
                onPressed: _busy || _loading ? null : _submit,
                child: Text(_busy
                    ? 'กำลังบันทึก…'
                    : _pending == null
                        ? 'บันทึก'
                        : 'ตรวจผล / ลองใหม่'))
          ],
        ));
  }
}

class StaffStockHistory extends StatefulWidget {
  const StaffStockHistory(
      {super.key, required this.productId, required this.api});
  final String productId;
  final StaffInventoryApi api;
  @override
  State<StaffStockHistory> createState() => _StaffStockHistoryState();
}

class _StaffStockHistoryState extends State<StaffStockHistory> {
  DateTimeRange? _range;
  final List<Map> _rows = [];
  bool _busy = false;
  String? _cursor, _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _rows.clear();
        _cursor = null;
      }
    });
    try {
      final data = await widget.api.call('stockHistory', {
        'productId': widget.productId,
        if (_cursor != null) 'cursor': _cursor,
        if (_range != null) ...{
          'from': _range!.start.toUtc().toIso8601String(),
          'to':
              DateTime(_range!.end.year, _range!.end.month, _range!.end.day + 1)
                  .toUtc()
                  .toIso8601String()
        }
      });
      if (mounted) {
        setState(() {
          _rows.addAll((data['records'] as List).cast<Map>());
          _cursor = data['nextCursor'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('ประวัติสต๊อก', style: Theme.of(context).textTheme.titleMedium),
        const Text('รายการก่อนเริ่มระบบสต๊อกดูได้จากประวัติการขาย'),
        Wrap(spacing: 8, children: [
          TextButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(_range == null
                  ? 'เลือกช่วงวันที่'
                  : '${DateFormat('dd/MM/yyyy').format(_range!.start)} – ${DateFormat('dd/MM/yyyy').format(_range!.end)}'),
              onPressed: _busy
                  ? null
                  : () async {
                      final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _range);
                      if (range != null && mounted) {
                        setState(() => _range = range);
                        await _load(reset: true);
                      }
                    }),
          if (_range != null)
            TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() => _range = null);
                        _load(reset: true);
                      },
                child: const Text('ทุกช่วงเวลา'))
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          TextButton(
              onPressed: _busy ? null : () => _load(),
              child: Text('$_error · ลองใหม่')),
        if (!_busy && _error == null && _rows.isEmpty)
          const Text('ยังไม่มีประวัติในช่วงนี้'),
        for (final m in _rows)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${const {
                    'opening': 'ยอดเริ่มต้น',
                    'receive': 'รับเข้า',
                    'count': 'ตรวจนับ',
                    'waste': 'ของเสีย / ตัดออก',
                    'sale': 'ขาย',
                    'refund': 'คืนสินค้า'
                  }[m['kind']] ?? m['kind']} ${(m['delta'] as num) > 0 ? '+' : ''}${stockText(m['delta'] as num)} ${m['unit']}'),
              subtitle: Text([
                if (m['createdAt'] != null)
                  'บันทึก: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(m['createdAt'] as String).toLocal())}',
                if (m['saleAt'] != null)
                  'วันขาย: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(m['saleAt'] as String).toLocal())}',
                'ก่อน ${stockText(m['before'] as num)} → หลัง ${stockText(m['after'] as num)} ${m['unit']}',
                'ผู้ทำรายการ: ${m['actorName']}',
                if (m['reason'] != '') 'เหตุผล: ${m['reason']}',
                if (m['documentNumber'] != '') 'เอกสาร: ${m['documentNumber']}',
                if (m['referenceId'] != '') 'อ้างอิง: ${m['referenceId']}',
                for (final l in m['lots'] as List)
                  'ล็อต ${l['number']} · หมดอายุ ${l['expiresOn']}',
                if (m.containsKey('totalCost'))
                  'ต้นทุนรวม ฿${(m['totalCost'] as num).toStringAsFixed(2)}',
              ].join('\n'))),
        if (_cursor != null)
          TextButton(
              onPressed: _busy ? null : () => _load(),
              child: const Text('โหลดประวัติเพิ่มเติม')),
      ]);
}
