import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../services/ai_service.dart';
import '../utils/operation_error.dart';
import '../widgets/shop_operation.dart';

String analysisMoney(dynamic value) => value == null
    ? 'ข้อมูลไม่ครบ'
    : '฿${NumberFormat('#,##0.00').format(value)}';
List<Map<String, dynamic>> analysisRows(dynamic rows) => (rows as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class SalesAnalysisScreen extends StatefulWidget {
  final int days;
  final Map<String, dynamic>? initial;
  const SalesAnalysisScreen({super.key, this.days = 30, this.initial});
  @override
  State<SalesAnalysisScreen> createState() => _SalesAnalysisScreenState();
}

class _SalesAnalysisScreenState extends State<SalesAnalysisScreen> {
  Map<String, dynamic>? _report;
  String? _error;
  bool _busy = false;
  String _sourcePeriod = 'current';
  late int _days;
  @override
  void initState() {
    super.initState();
    _days = widget.initial?['days'] as int? ?? widget.days;
    _report = widget.initial;
    if (_report == null) _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await AiService.analysis(_days);
      if (mounted) setState(() => _report = report);
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _metric(String label, dynamic value) =>
      ListTile(title: Text(label), trailing: Text(analysisMoney(value)));
  Widget _text(String text) =>
      Padding(padding: const EdgeInsets.all(12), child: Text(text));
  Widget _overview(Map<String, dynamic> r) {
    final c = r['current'] as Map,
        p = r['previous'] as Map,
        today = r['today'] as Map;
    return ListView(children: [
      _text(
          'ช่วงปัจจุบัน ${c['from']} – ${c['through']}\nเทียบ ${p['from']} – ${p['through']}\nเขตเวลา ${r['timeZone']}'),
      _metric('ยอดสุทธิช่วงปัจจุบัน', c['net']),
      _metric('ยอดสุทธิช่วงก่อน', p['net']),
      _text(
          'เปลี่ยนแปลง ${analysisMoney(r['change'])} · ${r['changePercent'] == null ? 'ไม่มีฐานยอดเดิมสำหรับคำนวณ %' : '${r['changePercent']}%'}'),
      _text('${c['count']} บิลที่ไม่คืนเงิน · ${c['units']} ชิ้น'),
      _metric('เฉลี่ยต่อบิล', c['average']),
      _metric('ยอดก่อนส่วนลด (รวมบิลคืนเงิน)', c['gross']),
      _metric('ส่วนลดท้ายบิล', c['discount']),
      _metric('บิลคืนเงิน', c['refunds']),
      _metric('ค่าบริการจากบิลที่ไม่คืนเงิน', c['service']),
      _metric('ยอดปรับ/เศษสตางค์', c['adjustment']),
      _metric('กำไรขั้นต้นสินค้า', c['grossProfit']),
      _text(
          'ต้นทุนครบ ${c['costCoverage'] ?? 0}% ของจำนวนชิ้น · ทราบต้นทุน ${c['knownUnits']}/${c['units']} ชิ้น'),
      if (c['grossProfit'] == null)
        _metric('กำไรเฉพาะส่วนที่ทราบต้นทุน', c['partialProfit']),
      _metric('วันนี้ (ยังไม่จบวัน ไม่ใช้เทียบ)', today['net']),
      for (final period in [c, p, today]) ...[
        if ((period['invalid'] as num) > 0)
          _text(
              'ช่วง ${period['from']}: ข้อมูลบิลผิดรูปแบบ ${period['invalid']} รายการไม่ถูกนำมาคำนวณ'),
        if ((period['unknownCategory'] as num) > 0)
          _text(
              'ช่วง ${period['from']}: ${period['unknownCategory']} รายการไม่มีหมวดหมู่ ณ เวลาขาย'),
        if ((period['estimatedPaidAt'] as num) > 0)
          _text(
              'ช่วง ${period['from']}: ${period['estimatedPaidAt']} ออเดอร์ไม่มีเวลารับเงิน ใช้เวลาสร้างแทน'),
      ],
      ExpansionTile(title: const Text('วิธีคำนวณและข้อจำกัด'), children: [
        for (final note in r['notes'] as List) _text(note.toString())
      ]),
    ]);
  }

  Widget _products(Map<String, dynamic> r) {
    final c = r['current'] as Map;
    return ListView(children: [
      _text('สินค้าเรียงตามยอดหลังส่วนลด ไม่รวมค่าบริการและบิลคืนเงิน'),
      for (final p in analysisRows(c['products']))
        ListTile(
            title: Text(p['name'].toString()),
            subtitle:
                Text('${p['units']} ชิ้น · กำไร ${analysisMoney(p['profit'])}'),
            trailing: Text(analysisMoney(p['net']))),
      if (analysisRows(c['products']).isEmpty) _text('ไม่มีรายการขายในช่วงนี้'),
      ExpansionTile(
          title: const Text('สินค้าที่ทำให้ยอดเปลี่ยน (ต่ำสุดไปสูงสุด)'),
          children: [
            for (final p in analysisRows(r['productChanges']))
              ListTile(
                  title: Text(p['name'].toString()),
                  subtitle: Text(
                      '${analysisMoney(p['previous'])} → ${analysisMoney(p['current'])}'),
                  trailing: Text(analysisMoney(p['difference']))),
          ]),
      ExpansionTile(title: const Text('ยอดตามหมวดหมู่ ณ เวลาขาย'), children: [
        for (final p in analysisRows(c['categories']))
          _metric(p['name'].toString(), p['net']),
      ]),
    ]);
  }

  Widget _time(Map<String, dynamic> r) {
    final current = r['current'] as Map, previous = r['previous'] as Map;
    final rows = analysisRows(current['daily']),
        prior = analysisRows(previous['daily']);
    final max = rows.fold<double>(
        1,
        (m, r) => (r['net'] as num).toDouble() > m
            ? (r['net'] as num).toDouble()
            : m);
    return ListView(children: [
      _text('ยอดรายวัน · แถบแสดงยอดสุทธิ วันที่ไม่มียอดแสดง 0'),
      for (var i = 0; i < rows.length; i++)
        ListTile(
          title: Text('${rows[i]['day']} · ${analysisMoney(rows[i]['net'])}'),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            LinearProgressIndicator(
                value: ((rows[i]['net'] as num) / max).clamp(0, 1).toDouble()),
            Text(
                'เทียบ ${prior[i]['day']} · ${analysisMoney(prior[i]['net'])}'),
          ]),
        ),
      ExpansionTile(
          title: const Text('ช่วงชั่วโมงที่ขายดี (เวลาร้าน)'),
          children: [
            for (final row in analysisRows(current['hours']))
              _metric('${row['hour']}:00 – ${row['hour']}:59', row['net']),
          ]),
    ]);
  }

  Widget _sources(Map<String, dynamic> r) {
    final rows = analysisRows((r[_sourcePeriod] as Map)['sources']);
    return Column(children: [
      Wrap(spacing: 8, children: [
        for (final entry in {
          'current': 'ช่วงปัจจุบัน',
          'previous': 'ช่วงก่อน',
          'today': 'วันนี้'
        }.entries)
          ChoiceChip(
              label: Text(entry.value),
              selected: _sourcePeriod == entry.key,
              onSelected: (_) => setState(() => _sourcePeriod = entry.key)),
      ]),
      Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('ไม่มีบิลในช่วงนี้'))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final s = rows[i];
                    return ExpansionTile(
                        title: Text(
                            '${s['day']} ${s['time']} · ${analysisMoney(s['total'])}'),
                        subtitle: Text(
                            '${s['source'] == 'orders' ? 'ออเดอร์ออนไลน์' : 'บิลขาย'} ${s['receipt']}${s['refunded'] == true ? ' · คืนเงินแล้ว' : ''}'),
                        children: [
                          _text(
                              'ข้อมูลต้นทาง ${s['source']}/${s['id']}\nสำเนาที่ใช้คำนวณรายงานนี้ ไม่รวมชื่อหรือเบอร์ลูกค้า'),
                          for (final item in analysisRows(s['items']))
                            ListTile(
                                title: Text(
                                    '${item['name']} × ${item['quantity']}'),
                                subtitle: Text(
                                    'ต้นทุนต่อชิ้น ${analysisMoney(item['cost'])}'),
                                trailing:
                                    Text(analysisMoney(item['subtotal']))),
                        ]);
                  })),
    ]);
  }

  Future<void> _settings() async {
    final settings =
        Map<String, dynamic>.from(_report?['settings'] as Map? ?? {});
    var zone = settings['timeZone'] as String? ?? 'Asia/Bangkok';
    final weekdays =
        ((settings['openWeekdays'] as List?) ?? []).cast<int>().toSet();
    const labels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final save = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('บริบทการเปิดร้าน'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                      initialValue: zone,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'เขตเวลาร้าน'),
                      items: {
                        ...[
                          'Asia/Bangkok',
                          'Australia/Sydney',
                          'Australia/Melbourne',
                          'Australia/Perth',
                          'UTC'
                        ],
                        zone
                      }
                          .map(
                              (z) => DropdownMenuItem(value: z, child: Text(z)))
                          .toList(),
                      onChanged: (v) => update(() => zone = v!),
                    ),
                    const SizedBox(height: 12),
                    const Text('วันเปิดตามปกติ (ไม่เลือก = ยังไม่ระบุ)'),
                    Wrap(spacing: 4, children: [
                      for (var i = 1; i <= 7; i++)
                        FilterChip(
                            label: Text(labels[i - 1]),
                            selected: weekdays.contains(i),
                            onSelected: (v) => update(
                                () => v ? weekdays.add(i) : weekdays.remove(i)))
                    ]),
                    const Text(
                        'วันหยุดพิเศษให้เพิ่มบันทึกปิดร้าน ข้อมูลนี้ไม่แก้ไขเวลาบนบิลเดิม'),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('บันทึก'))
                  ],
                )));
    if (save != true || !mounted) return;
    if (await performShopOperation(
        context,
        () => AiService.saveContext({
              'settings': {'timeZone': zone, 'openWeekdays': weekdays.toList()}
            }))) {
      await _load();
    }
  }

  Future<void> _addEvent() async {
    final ctrl = TextEditingController();
    var type = 'closed';
    DateTimeRange? range;
    final id = const Uuid().v4();
    final save = await showDialog<bool>(
        context: context,
        builder: (_) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('เพิ่มบริบทช่วงวันที่'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration:
                            const InputDecoration(labelText: 'เหตุการณ์'),
                        items: const [
                          DropdownMenuItem(
                              value: 'closed', child: Text('ปิดร้าน')),
                          DropdownMenuItem(
                              value: 'promotion', child: Text('โปรโมชัน')),
                          DropdownMenuItem(
                              value: 'stockout', child: Text('สินค้าหมด')),
                          DropdownMenuItem(
                              value: 'other', child: Text('เหตุการณ์อื่น')),
                        ],
                        onChanged: (v) => update(() => type = v!)),
                    TextButton(
                        onPressed: () async {
                          final selected = await showDateRangePicker(
                              context: ctx,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)));
                          if (ctx.mounted && selected != null) {
                            update(() => range = selected);
                          }
                        },
                        child: Text(range == null
                            ? 'เลือกช่วงวันที่ตามปฏิทินร้าน'
                            : '${DateFormat('yyyy-MM-dd').format(range!.start)} – ${DateFormat('yyyy-MM-dd').format(range!.end)}')),
                    TextField(
                        controller: ctrl,
                        maxLength: 500,
                        maxLines: 3,
                        onChanged: (_) => update(() {}),
                        decoration: const InputDecoration(
                            labelText: 'รายละเอียด / ชื่อสินค้าที่เกี่ยวข้อง')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('ยกเลิก')),
                    FilledButton(
                        onPressed: range == null || ctrl.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('บันทึก'))
                  ],
                )));
    final note = ctrl.text;
    Future<void>.delayed(const Duration(milliseconds: 400), ctrl.dispose);
    if (save != true || !mounted) return;
    final ok = await performShopOperation(
        context,
        () => AiService.saveContext({
              'id': id,
              'type': type,
              'startDay': DateFormat('yyyy-MM-dd').format(range!.start),
              'endDay': DateFormat('yyyy-MM-dd').format(range!.end),
              'note': note
            }));
    if (ok) await _load();
  }

  Widget _context(Map<String, dynamic> r) => ListView(children: [
        ListTile(
            title: const Text('วันเปิดและเขตเวลาร้าน'),
            subtitle: Text(
                '${r['timeZone']} · วันเปิด ${(r['settings'] as Map)['openWeekdays']} (1=จันทร์, 7=อาทิตย์)'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _busy ? null : _settings),
        Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
                onPressed: _busy ? null : _addEvent,
                icon: const Icon(Icons.add),
                label: const Text('บันทึกปิดร้าน / โปรโมชัน / สินค้าหมด'))),
        _text(
            'ระบบบันทึกการเปลี่ยนสต็อกหมด/เติมกลับและการตั้งราคาโปรตั้งแต่เปิดใช้ฟีเจอร์ บันทึกย้อนหลังเพิ่มเองได้ ประวัตินี้เป็นข้อมูลประกอบ ไม่ยืนยันสาเหตุของยอดขาย'),
        _text(
            'เพื่อให้กำไรครบ: ระบุราคาทุนในเมนูสินค้า และต้นทุนเพิ่มของตัวเลือกอาหารในกลุ่มตัวเลือก บิลเก่าจะไม่ถูกเปลี่ยนตามราคาทุนใหม่'),
        ExpansionTile(
            title: const Text('สินค้าใกล้หมดตอนดึงรายงาน (ไม่รวมสูตรวัตถุดิบ)'),
            children: [
              for (final p
                  in analysisRows((_report?['inventory'] as Map?)?['lowStock']))
                ListTile(
                    title: Text(p['name'].toString()),
                    trailing: Text('${p['stock']} ชิ้น')),
            ]),
        for (final e in analysisRows(r['events']))
          ListTile(
            title: Text('${{
                  'closed': 'ปิดร้าน',
                  'promotion': 'โปรโมชัน',
                  'stockout': 'สินค้าหมด',
                  'restock': 'เติมสินค้า',
                  'promotion_change': 'เปลี่ยนราคาโปร',
                  'other': 'อื่น ๆ'
                }[e['type']] ?? e['type']} · ${e['startDay']} – ${e['endDay']}'),
            subtitle: Text(
                '${e['note']}\n${e['source'] == 'owner' ? 'บันทึกโดยร้าน' : 'บันทึกอัตโนมัติ'}'),
            trailing: e['source'] != 'owner'
                ? null
                : IconButton(
                    tooltip: 'ลบบันทึก',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: _busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                        title: const Text('ลบบันทึกนี้?'),
                                        content: Text(e['note'].toString()),
                                        actions: [
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('ยกเลิก')),
                                          TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('ลบ'))
                                        ]));
                            if (confirmed != true || !mounted) return;
                            if (await performShopOperation(
                                context,
                                () => AiService.saveContext(
                                    {'deleteId': e['id']}))) {
                              await _load();
                            }
                          }),
          ),
      ]);
  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('รายงานสำหรับวิเคราะห์'),
            actions: [
              IconButton(
                  tooltip: 'ดึงรายงานล่าสุด',
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh))
            ],
            bottom: const TabBar(isScrollable: true, tabs: [
              Tab(text: 'ภาพรวม'),
              Tab(text: 'สินค้า'),
              Tab(text: 'เวลา'),
              Tab(text: 'บิลต้นทาง'),
              Tab(text: 'บริบท')
            ])),
        body: Column(children: [
          Wrap(spacing: 8, children: [
            for (final d in [7, 30, 90])
              ChoiceChip(
                  label: Text('$d วัน'),
                  selected: _days == d,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() {
                            _days = d;
                            _report = null;
                          });
                          _load();
                        })
          ]),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    '$_error${_report != null ? '\nกำลังแสดงรายงานเดิม' : ''}')),
          if (_report != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                    'ดึงข้อมูล ${_report!['generatedAt']} · เขตเวลา ${_report!['timeZone']}',
                    style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child: _report == null
                  ? Center(
                      child: _busy
                          ? const Text('กำลังรวบรวมบิลจากระบบ...')
                          : TextButton(
                              onPressed: _load, child: const Text('ลองใหม่')))
                  : TabBarView(children: [
                      _overview(_report!),
                      _products(_report!),
                      _time(_report!),
                      _sources(_report!),
                      _context(_report!)
                    ])),
        ]),
      ));
}
