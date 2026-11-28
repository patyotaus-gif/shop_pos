import 'package:flutter/material.dart';
import '../services/staff_access_service.dart';
import '../utils/operation_error.dart';
import '../widgets/content_width.dart';

typedef BranchCall = Future<Map<String, dynamic>> Function(
    String name, Map<String, dynamic> data);

const _statuses = {
  'pending': 'รอพิจารณา',
  'approved': 'อนุมัติแล้ว',
  'moreInfo': 'ต้องการข้อมูลเพิ่ม',
  'declined': 'ไม่อนุมัติ',
};

class BranchRequestsScreen extends StatefulWidget {
  const BranchRequestsScreen.owner(
      {super.key,
      required String this.shopId,
      this.call = StaffAccessService.call});
  const BranchRequestsScreen.admin(
      {super.key, this.call = StaffAccessService.call})
      : shopId = null;
  final String? shopId;
  final BranchCall call;

  @override
  State<BranchRequestsScreen> createState() => _BranchRequestsScreenState();
}

class _BranchRequestsScreenState extends State<BranchRequestsScreen> {
  bool get admin => widget.shopId == null;
  Future<Map<String, dynamic>> _call(Map<String, dynamic> data) => widget.call(
      admin ? 'adminBranchRequests' : 'merchantBranchRequests',
      {if (!admin) 'shopId': widget.shopId, ...data});
  late Future<Map<String, dynamic>> _data = _call({'action': 'list'});

  void _reload() {
    setState(() {
      _data = _call({'action': 'list'});
    });
  }

  void _saved() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(admin ? 'บันทึกผลพิจารณาแล้ว' : 'ส่งคำขอให้ผู้ดูแลแล้ว')));
    _reload();
  }

  Future<void> _open(Map<String, dynamic> result, [Map? item]) async {
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (page) => Scaffold(
                appBar: AppBar(
                    title: Text(admin
                        ? 'พิจารณาคำขอ'
                        : item == null
                            ? 'ขอเพิ่มสาขา'
                            : 'ยื่นคำขออีกครั้ง')),
                body: SafeArea(
                    child: ContentWidth(
                        maxWidth: 640,
                        child: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              if (!admin) _ShopTerms(result),
                              _BranchForm(
                                  admin: admin,
                                  item: item,
                                  call: _call,
                                  onSaved: () {
                                    if (ModalRoute.of(page)?.isCurrent ==
                                        true) {
                                      Navigator.pop(page, true);
                                    }
                                  }),
                            ]))))));
    if (mounted && saved == true) _saved();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(admin ? 'คำขอเพิ่มสาขา' : 'สาขาของร้าน'),
            actions: [
              TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('เช็กสถานะ')),
            ]),
        body: SafeArea(
            child: ContentWidth(
                maxWidth: 640,
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _data,
                  builder: (context, snap) {
                    if (!snap.hasData &&
                        snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError || !snap.hasData) {
                      return Center(
                          child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(operationError(snap.error ??
                                        StateError('โหลดข้อมูลสาขาไม่สำเร็จ'))),
                                    TextButton(
                                        onPressed: _reload,
                                        child: const Text('ลองอีกครั้ง')),
                                  ])));
                    }
                    final result = snap.data!,
                        items = (result['items'] as List).cast<Map>();
                    return ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (!admin) _ShopTerms(result),
                          if (items.isEmpty && !admin)
                            _BranchForm(
                                admin: false, call: _call, onSaved: _saved)
                          else ...[
                            if (!admin) ...[
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                      onPressed: () => _open(result),
                                      icon: const Icon(Icons.add),
                                      label: const Text('ขอเพิ่มสาขา'))),
                              const SizedBox(height: 24),
                            ],
                            Text(admin ? 'รอพิจารณา' : 'คำขอของร้าน',
                                style: Theme.of(context).textTheme.titleLarge),
                            if (items.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.only(top: 12),
                                  child: Text('ไม่มีคำขอที่รอพิจารณา')),
                            for (final item in items)
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(item['name'] as String,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            if (admin)
                                              Text(item['shopName'] as String),
                                            Text(item['address'] as String),
                                            const SizedBox(height: 6),
                                            if (!admin)
                                              Text(_statuses[item['status']] ??
                                                  'ไม่ทราบสถานะ'),
                                            if ((item['reason'] as String)
                                                .isNotEmpty)
                                              Text(
                                                  'เหตุผลจากผู้ดูแล · ${item['reason']}'),
                                            if (admin ||
                                                ['moreInfo', 'declined']
                                                    .contains(item['status']))
                                              Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: TextButton(
                                                      onPressed: () =>
                                                          _open(result, item),
                                                      child: Text(admin
                                                          ? 'พิจารณาคำขอ'
                                                          : item['status'] ==
                                                                  'declined'
                                                              ? 'ขอทบทวน'
                                                              : 'ส่งข้อมูลเพิ่มเติม'))),
                                          ]))),
                          ],
                        ]);
                  },
                ))),
      );
}

String _terms(BuildContext context, Map data) {
  final end = data['endsAtMs'] as int?;
  final date = end == null
      ? null
      : MaterialLocalizations.of(context)
          .formatShortDate(DateTime.fromMillisecondsSinceEpoch(end));
  return switch (data['planStatus']) {
    'trial' when date != null => 'ใช้สิทธิ์ทดลองเดิมถึง $date',
    'active' when date != null => 'ใช้แพ็กเกจเดิมถึง $date',
    'expired' => 'ใช้สิทธิ์ตามร้านเดิม (แพ็กเกจหมดอายุ)',
    _ => 'ใช้สิทธิ์ตามร้านเดิม',
  };
}

class _ShopTerms extends StatelessWidget {
  const _ShopTerms(this.data);
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.storefront_outlined),
            const SizedBox(width: 10),
            Expanded(
                child: Text(data['shopName'] as String,
                    style: Theme.of(context).textTheme.titleLarge))
          ]),
          const SizedBox(height: 8),
          Text('สาขาใหม่${_terms(context, data)}'),
        ]));
  }
}

class _BranchForm extends StatefulWidget {
  const _BranchForm(
      {required this.admin,
      required this.call,
      required this.onSaved,
      this.item});
  final bool admin;
  final Map? item;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) call;
  final VoidCallback onSaved;
  @override
  State<_BranchForm> createState() => _BranchFormState();
}

class _BranchFormState extends State<_BranchForm> {
  final _form = GlobalKey<FormState>();
  late String _name = widget.item?['name'] ?? '',
      _address = widget.item?['address'] ?? '',
      _note = widget.item?['note'] ?? '';
  String? _decision, _error;
  String _reason = '';
  bool _busy = false;
  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'กรุณากรอกช่องนี้' : null;

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final revision = widget.item?['revision'] ?? 0;
      await widget.call(widget.admin
          ? {
              'action': _decision,
              'id': widget.item!['id'],
              'revision': revision,
              'reason': _reason.trim()
            }
          : {
              'action': 'submit',
              'revision': revision,
              'name': _name.trim(),
              'address': _address.trim(),
              'note': _note.trim()
            });
      if (mounted) widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = operationError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Form(
        key: _form,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.admin && item != null) ...[
            Text(item['name'] as String,
                style: Theme.of(context).textTheme.titleLarge),
            Text('ร้านต้นสังกัด · ${item['shopName']}'),
            if (item['ownerEmail'] != '')
              SelectableText('บัญชีร้าน · ${item['ownerEmail']}'),
            Text('ที่ตั้ง · ${item['address']}'),
            if (item['termsAtSubmission'] is Map)
              Text(
                  'สิทธิ์เมื่อยื่นคำขอ · ${_terms(context, item['termsAtSubmission'] as Map)}'),
            if ((item['previousReason'] ?? '') != '')
              Text('ผลพิจารณาครั้งก่อน · ${item['previousReason']}'),
            if (item['note'] != '') Text('ข้อมูลจากเจ้าของ · ${item['note']}'),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'ผลพิจารณา'),
                items: const [
                  DropdownMenuItem(
                      value: 'approved', child: Text('อนุมัติเพิ่มสาขา')),
                  DropdownMenuItem(
                      value: 'moreInfo', child: Text('ขอข้อมูลเพิ่มเติม')),
                  DropdownMenuItem(value: 'declined', child: Text('ไม่อนุมัติ'))
                ],
                onChanged: _busy ? null : (v) => setState(() => _decision = v),
                validator: (v) => v == null ? 'กรุณาเลือกผลพิจารณา' : null),
            const SizedBox(height: 16),
            TextFormField(
                enabled: !_busy,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'เหตุผลที่แจ้งเจ้าของร้าน (จำเป็น)'),
                validator: _required,
                onChanged: (v) => _reason = v),
          ] else ...[
            Text(item == null ? 'ขอเพิ่มสาขา' : 'ข้อมูลสาขา',
                style: Theme.of(context).textTheme.titleLarge),
            if (item?['reason'] != null)
              Text('เหตุผลจากผู้ดูแล · ${item!['reason']}'),
            const SizedBox(height: 16),
            TextFormField(
                initialValue: _name,
                readOnly: item != null,
                enabled: !_busy,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'ชื่อสาขา', hintText: 'เช่น สาขาตลาดเช้า'),
                validator: _required,
                onChanged: (v) => _name = v),
            const SizedBox(height: 8),
            TextFormField(
                initialValue: _address,
                enabled: !_busy,
                maxLength: 400,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'ที่ตั้งสาขา',
                    hintText: 'ที่อยู่ อำเภอ และจังหวัด'),
                validator: _required,
                onChanged: (v) => _address = v),
            const SizedBox(height: 8),
            TextFormField(
                initialValue: _note,
                enabled: !_busy,
                maxLength: 500,
                minLines: 1,
                maxLines: 4,
                decoration:
                    const InputDecoration(labelText: 'ข้อมูลเพิ่มเติม (ถ้ามี)'),
                onChanged: (v) => _note = v),
          ],
          if (_error != null)
            Semantics(
                liveRegion: true,
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _busy ? null : _send,
              child: Text(_busy
                  ? 'กำลังบันทึก…'
                  : widget.admin
                      ? 'บันทึกผลพิจารณา'
                      : 'ส่งคำขอเพิ่มสาขา')),
        ]));
  }
}
