import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/debt.dart';
import '../services/auth_service.dart';
import '../services/debt_service.dart';
import '../widgets/shop_operation.dart';

class MoneyMovementsScreen extends StatefulWidget {
  const MoneyMovementsScreen({super.key});
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
    await showDialog<void>(
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
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                labels[row['type']] ?? row['type'].toString()),
                            subtitle: SelectableText(row['id'].toString()),
                            trailing: Text('฿${_money.format(row['amount'])}')),
                    ],
                  ))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ปิด'))
              ],
            ));
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
                      ((row.data()['amountMinor'] as num?)?.toInt() ?? 0));
              final cash = rows
                  .where((row) => row.data()['method'] == 'cash')
                  .fold<int>(
                      0,
                      (value, row) =>
                          value + (row.data()['amountMinor'] as num).toInt());
              return ListView(padding: const EdgeInsets.all(16), children: [
                Text(DateFormat('dd/MM/yyyy').format(_day),
                    style: Theme.of(context).textTheme.titleLarge),
                const Text(
                    'ตามวันที่บันทึกเงิน รวมรับชำระหนี้และคืนเงิน เริ่มเก็บตั้งแต่ระบบบัญชีรุ่นนี้ ยอดขายย้อนหลังดูในรายงานยอดขาย'),
                ListTile(
                    title: const Text('เงินรับสุทธิทุกช่องทาง'),
                    trailing: Text('฿${_money.format(received / 100)}')),
                ListTile(
                    title: const Text('เงินสดเพิ่ม / ลด'),
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
                for (final row in rows) _movement(row.data()),
              ]);
            }),
      );

  Widget _movement(Map<String, dynamic> row) {
    final title = switch (row['kind']) {
      'sale' => 'ขายสินค้า',
      'debtPayment' => 'รับชำระหนี้',
      'refund' => 'คืนเงิน',
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
      contentPadding: EdgeInsets.zero,
      title: Text('$title · $method'),
      subtitle: Text(
          '${row['saleId'] ?? ''}${row['needsReconciliation'] == true ? '\nยังไม่ผูกกับรอบขาย ต้องตรวจสอบ' : ''}'),
      trailing:
          Text('฿${_money.format((row['amountMinor'] as num? ?? 0) / 100)}'),
    );
  }
}
