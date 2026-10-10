import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/debt.dart';
import '../services/auth_service.dart';
import '../services/debt_service.dart';
import '../widgets/shop_operation.dart';
import '../services/cash_movement_service.dart';
import '../widgets/cash_movement_dialog.dart';
import '../widgets/cash_reconciliation_dialog.dart';
import '../utils/operation_error.dart';

class MoneyMovementsScreen extends StatefulWidget {
  const MoneyMovementsScreen({super.key, this.initialMovementId});
  final String? initialMovementId;
  @override
  State<MoneyMovementsScreen> createState() => _MoneyMovementsScreenState();
}

class _MoneyMovementsScreenState extends State<MoneyMovementsScreen> {
  late DateTime _day;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  final _money = NumberFormat('#,##0.00', 'th_TH');
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _setDay(DateTime(now.year, now.month, now.day));
    if (widget.initialMovementId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolve(widget.initialMovementId!);
      });
    }
  }

  bool _resolving = false;
  Future<void> _resolve(String id) async {
    if (_resolving) return;
    _resolving = true;
    try {
      final shopId = AuthService.shopId;
      final shop = FirebaseFirestore.instance.collection('shops').doc(shopId);
      Map<String, dynamic>? movement, session;
      String? sessionId;
      final loaded = await performShopOperation(context, () async {
        movement = (await shop
                .collection('moneyMovements')
                .doc(id)
                .get(const GetOptions(source: Source.server)))
            .data();
        final control = await shop
            .collection('cashControl')
            .doc('current')
            .get(const GetOptions(source: Source.server));
        sessionId = control.data()?['sessionId'] as String?;
        if (sessionId != null) {
          session = (await shop
                  .collection('cashSessions')
                  .doc(sessionId)
                  .get(const GetOptions(source: Source.server)))
              .data();
        }
        if (movement?['needsReconciliation'] != true) {
          throw StateError(
              'รายการนี้ไม่ค้างแล้ว กรุณากลับไปตรวจปิดยอดอีกครั้ง');
        }
        if (session?['status'] != 'open' ||
            session?['accountingVersion'] != 1) {
          throw StateError('เปิดรอบขายก่อนจัดรายการเงินเข้ารอบ');
        }
      }, success: 'โหลดรายการรอตรวจสอบแล้ว');
      if (!loaded || !mounted) return;
      final amount = (movement!['amountMinor'] as num).toInt();
      await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CashReconciliationDialog(
              movementId: id,
              amountMinor: amount,
              method: movement!['method'] as String,
              kind: movement!['kind'] as String,
              recordedAt: (movement!['recordedAt'] as Timestamp?)?.toDate(),
              openedAt: (session!['openedAt'] as Timestamp).toDate(),
              openingFloat: (session!['openingFloat'] as num).toDouble(),
              save: (reason, cashTreatment) async {
                await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
                    .httpsCallable('reconcileCashMovement')
                    .call({
                  'shopId': shopId,
                  'movementId': id,
                  'sessionId': sessionId,
                  'expectedAmountMinor': amount,
                  'reason': reason,
                  'cashTreatment': cashTreatment,
                });
              }));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(operationError(error))));
      }
    } finally {
      _resolving = false;
    }
  }

  void _setDay(DateTime day) {
    _day = day;
    _stream = FirebaseFirestore.instance
        .collection('shops')
        .doc(AuthService.shopId)
        .collection('moneyMovements')
        .where('recordedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(day))
        .where('recordedAt',
            isLessThan:
                Timestamp.fromDate(DateTime(day.year, day.month, day.day + 1)))
        .orderBy('recordedAt', descending: true)
        .snapshots();
  }

  Future<void> _review() async {
    Map<String, dynamic>? data;
    final ok = await performShopOperation(context, () async {
      final result =
          await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
              .httpsCallable('getAccountingReview')
              .call({'shopId': AuthService.shopId});
      data = Map<String, dynamic>.from(result.data);
    }, success: 'ตรวจรายการแล้ว ไม่มีการแก้ข้อมูล');
    if (!ok || !mounted) return;
    final rows = (data!['findings'] as List).cast<Map>();
    const labels = {
      'missingSale': 'ออเดอร์รับเงินแล้วแต่ไม่มีบิลขาย',
      'duplicateSale': 'มีบิลขายเชื่อมออเดอร์มากกว่าหนึ่งบิล',
      'unassignedMovement': 'เงินที่ยังไม่ผูกกับรอบขาย',
      'legacySession': 'รอบเก่าที่ต้องตรวจยอด'
    };
    final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('รายการรอตรวจสอบ'),
              content: SizedBox(
                  width: 540,
                  child: SingleChildScrollView(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data!['scope'] as String),
                      if (data!['truncated'] == true)
                        const Text(
                            'มีข้อมูลเกินขอบเขตที่ตรวจ ต้องตรวจส่วนที่เหลือเพิ่มเติม'),
                      if (rows.isEmpty)
                        const Text('ไม่พบรายการผิดปกติในขอบเขตที่ตรวจ'),
                      for (final row in rows)
                        ListTile(
                            onTap: row['type'] == 'unassignedMovement'
                                ? () => Navigator.pop(ctx, row['id'].toString())
                                : null,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                labels[row['type']] ?? row['type'].toString()),
                            subtitle: Text(
                                '${row['id']}${row['type'] == 'unassignedMovement' ? '\nแตะเพื่อตรวจและจัดเข้ารอบ' : ''}'),
                            trailing: Text('฿${_money.format(row['amount'])}')),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ปิด'))
              ],
            ));
    if (selected != null && mounted) await _resolve(selected);
  }

  bool _adding = false;
  Future<void> _addMovement() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final pending = await CashMovementService.pending();
      if (!mounted) return;
      final saved = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CashMovementDialog(
              pending: pending, save: CashMovementService.record));
      if (saved == true && mounted) {
        final now = DateTime.now();
        setState(() => _setDay(DateTime(now.year, now.month, now.day)));
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกเงินสดเข้า–ออกแล้ว')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('เปิดรายการเงินไม่สำเร็จ กรุณาลองใหม่')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เงินเข้า–ออก'), actions: [
          IconButton(
              tooltip: 'เลือกวัน',
              icon: const Icon(Icons.calendar_month),
              onPressed: () async {
                final day = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now());
                if (day != null && mounted) setState(() => _setDay(day));
              }),
        ]),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(
                    child: Text(
                        'โหลดประวัติเงินไม่สำเร็จ กรุณาตรวจสอบการเชื่อมต่อ'));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data!.docs;
              final received = rows.fold<int>(
                  0,
                  (value, row) =>
                      value +
                      (['cashIn', 'cashOut'].contains(row.data()['kind'])
                          ? 0
                          : ((row.data()['amountMinor'] as num?)?.toInt() ??
                              0)));
              final cash = rows
                  .where((row) => row.data()['method'] == 'cash')
                  .fold<int>(
                      0,
                      (value, row) =>
                          value + (row.data()['amountMinor'] as num).toInt());
              return ListView(padding: const EdgeInsets.all(16), children: [
                Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                        onPressed: _adding ? null : _addMovement,
                        icon: const Icon(Icons.add),
                        label: const Text('บันทึกเงินเข้า–ออก'))),
                Text(DateFormat('dd/MM/yyyy').format(_day),
                    style: Theme.of(context).textTheme.titleLarge),
                const Text(
                    'ตามวันที่บันทึกเงิน รวมรับชำระหนี้และคืนเงิน เริ่มเก็บตั้งแต่ระบบบัญชีรุ่นนี้ ยอดขายย้อนหลังดูในรายงานยอดขาย'),
                ListTile(
                    title: const Text('รับชำระสุทธิทุกวิธีจ่าย'),
                    subtitle: const Text(
                        'รวมชำระหนี้ หักคืนเงิน ไม่รวมเงินเข้า–ออกที่บันทึกเอง'),
                    trailing: Text('฿${_money.format(received / 100)}')),
                ListTile(
                    title: const Text('เงินสดเพิ่ม / ลด'),
                    subtitle: const Text(
                        'รวมเงินเข้า–ออกที่บันทึกเอง ไม่รวมเงินทอนเริ่มต้น'),
                    trailing: Text('฿${_money.format(cash / 100)}')),
                StreamBuilder<List<Debt>>(
                    stream: DebtService.watchUnpaid(),
                    builder: (context, debts) => ListTile(
                          title: const Text('ลูกหนี้คงค้างปัจจุบัน'),
                          trailing: Text(debts.hasError
                              ? 'โหลดไม่สำเร็จ'
                              : !debts.hasData
                                  ? 'กำลังโหลด'
                                  : '฿${_money.format(debts.data!.fold<double>(0, (value, d) => value + d.remaining))}'),
                        )),
                OutlinedButton.icon(
                    onPressed: _review,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('ตรวจรายการที่ยอดอาจไม่ตรงกัน')),
                const Divider(),
                if (rows.isEmpty)
                  const Text('ไม่มีรายการเงินที่บันทึกในวันนี้'),
                for (final row in rows) _movement(row.id, row.data()),
              ]);
            }),
      );

  Widget _movement(String id, Map<String, dynamic> row) {
    final title = switch (row['kind']) {
      'sale' => 'ขายสินค้า',
      'debtPayment' => 'รับชำระหนี้',
      'refund' => 'คืนเงิน',
      'cashIn' => 'เงินสดเข้า',
      'cashOut' => 'เงินสดออก',
      _ => 'รายการเงิน'
    };
    final method = switch (row['method']) {
      'cash' => 'เงินสด',
      'transfer' => 'โอน',
      'qr' => 'QR',
      'credit' => 'ขายเชื่อ',
      _ => 'ออนไลน์'
    };
    return ListTile(
      onTap: row['needsReconciliation'] == true ? () => _resolve(id) : null,
      contentPadding: EdgeInsets.zero,
      title: Text('$title · $method'),
      subtitle: Text('${row['reason'] ?? row['saleId'] ?? ''}'
          '${row['recordedAt'] is Timestamp ? '\n${DateFormat('dd/MM/yyyy HH:mm').format((row['recordedAt'] as Timestamp).toDate())}' : ''}'
          '${row['needsReconciliation'] == true ? '\nยังไม่ผูกกับรอบขาย · แตะเพื่อตรวจและจัดเข้ารอบ' : ''}'
          '${row['reconciliation'] is Map ? '\nตรวจและจัดเข้ารอบแล้ว: ${row['reconciliation']['reason']}' : ''}'),
      trailing:
          Text('฿${_money.format((row['amountMinor'] as num? ?? 0) / 100)}'),
    );
  }
}
