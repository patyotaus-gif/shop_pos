import 'package:flutter/material.dart';
import 'cash_close_issue_screen.dart';
import 'package:intl/intl.dart';

import '../models/cash_session.dart';
import '../models/cash_close_check.dart';
import '../services/cash_session_service.dart';
import '../services/staff_service.dart';
import '../utils/zreport_generator.dart';
import '../widgets/shop_operation.dart';
import '../widgets/cash_close_blockers_dialog.dart';
import '../utils/operation_error.dart';
import 'money_movements_screen.dart';
import 'orders_screen.dart';
import 'tables_screen.dart';

/// ปิดยอดสิ้นวัน — open a cash session (with the drawer's starting float),
/// then close it: count the drawer, see over/short, print the Z-report.
class CashSessionScreen extends StatelessWidget {
  const CashSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ปิดยอดสิ้นวัน'), centerTitle: true),
      body: StreamBuilder<CashSession?>(
        stream: CashSessionService.watchOpen(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('โหลดรอบขายไม่สำเร็จ กรุณาตรวจสอบการเชื่อมต่อ'));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final open = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('เงินเข้า–ออกและรายการรอตรวจสอบ'),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MoneyMovementsScreen()))),
              if (open == null)
                _OpenCard()
              else
                _OpenSessionCard(session: open),
              const SizedBox(height: 24),
              Text('ประวัติรอบ',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              StreamBuilder<List<CashSession>>(
                stream: CashSessionService.watchHistory(),
                builder: (context, hs) {
                  if (hs.hasError) return const Text('โหลดประวัติไม่สำเร็จ');
                  if (!hs.hasData) return const LinearProgressIndicator();
                  final list =
                      (hs.data ?? const []).where((s) => s.closed).toList();
                  if (list.isEmpty) {
                    return Text('ยังไม่มีประวัติ',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5)));
                  }
                  return Column(
                    children: [for (final s in list) _HistoryTile(session: s)],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

final _baht = NumberFormat('#,##0.00', 'th_TH');
final _dt = DateFormat('dd/MM/yy HH:mm', 'th_TH');

class _OpenCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ยังไม่ได้เปิดรอบ',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('เปิดรอบตอนเช้าโดยใส่จำนวนเงินทอนในลิ้นชัก',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('เปิดรอบ'),
              onPressed: () => _openDialog(context),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openDialog(BuildContext context) async {
  var enabled = false;
  final loaded = await performShopOperation(context, () async {
    enabled = await CashSessionService.accountingEnabled();
  }, message: 'กำลังตรวจสถานะรอบขาย', success: 'ตรวจสถานะรอบขายแล้ว');
  if (!loaded || !context.mounted) return;
  var accepted = enabled;
  final ctrl = TextEditingController(text: '0');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
              title: const Text('เปิดรอบ'),
              content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'เงินทอนเริ่มต้นในลิ้นชัก (บาท)',
                      prefixText: '฿',
                      border: OutlineInputBorder()),
                ),
                if (!enabled) ...[
                  const SizedBox(height: 12),
                  const Text(
                      'เริ่มใช้ระบบปิดยอดใหม่กับร้านนี้ เมื่อเริ่มแล้วเครื่องรุ่นเก่าจะบันทึกการเงินไม่ได้ ต้องอัปเดต Android และ iOS ทุกเครื่องก่อน'),
                  const SizedBox(height: 8),
                  const Text(
                      'ระบบเริ่มนับจากรอบนี้ ยอดก่อนเริ่มยังเก็บไว้และต้องตรวจสอบแยก เงินสดเดิมในลิ้นชักให้รวมในเงินทอนเริ่มต้น'),
                  CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('อัปเดตทุกเครื่องและซิงก์บิลครบแล้ว'),
                      value: accepted,
                      onChanged: (value) =>
                          setDialogState(() => accepted = value == true)),
                ],
              ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('ยกเลิก')),
                FilledButton(
                    onPressed: accepted ? () => Navigator.pop(ctx, true) : null,
                    child: const Text('เปิดรอบ')),
              ],
            )),
  );
  if (ok != true) return;
  final float = double.tryParse(ctrl.text.trim().replaceAll(',', ''));
  ctrl.dispose();
  if (float == null || !float.isFinite || float < 0 || !context.mounted) return;
  final staff = await StaffService.getActive();
  if (!context.mounted) return;
  await performShopOperation(
      context,
      () => CashSessionService.open(
          openingFloat: float,
          openedBy: staff?.name,
          acknowledgeDeviceUpdate: accepted));
}

class _OpenSessionCard extends StatelessWidget {
  const _OpenSessionCard({required this.session});
  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_open, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                const Text('รอบกำลังเปิดอยู่',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text('เปิดเมื่อ ${_dt.format(session.openedAt)}'
                '${session.openedBy != null ? ' โดย ${session.openedBy}' : ''}'),
            Text('เงินทอนเริ่มต้น ฿${_baht.format(session.openingFloat)}'),
            if (session.accountingVersion != 1)
              const Text(
                  'รอบเก่า: ประวัติรับชำระหนี้และคืนเงินไม่ครบ ปิดเก็บยอดนับจริงไว้ตรวจสอบ แล้วเปิดรอบใหม่ได้'),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              icon: const Icon(Icons.stop),
              label: const Text('ปิดรอบ + นับเงิน'),
              onPressed: () => _closeDialog(context, session),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _closeDialog(BuildContext context, CashSession session) async {
  late final CashCloseCheck check;
  try {
    check = await runShopOperation(
        context, () => CashSessionService.checkClose(session),
        message: 'กำลังตรวจออเดอร์ บิลโต๊ะ และยอดเงินก่อนปิดรอบ');
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(operationError(error))));
    }
    return;
  }
  if (!context.mounted) return;
  if (!check.canClose) {
    CashCloseIssue? selectedIssue;
    final destination = await showDialog<CashCloseDestination>(
        context: context,
        builder: (ctx) => CashCloseBlockersDialog(
            check: check,
            onIssue: (issue) {
              selectedIssue = issue;
              Navigator.pop(ctx);
            }));
    if (!context.mounted || (destination == null && selectedIssue == null)) {
      return;
    }
    final Widget screen = selectedIssue != null
        ? CashCloseIssueScreen(issue: selectedIssue!)
        : switch (destination!) {
            CashCloseDestination.orders => const OrdersScreen(),
            CashCloseDestination.tables => const TablesScreen(),
            CashCloseDestination.money => const MoneyMovementsScreen(),
          };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (context.mounted) await _closeDialog(context, session);
    return;
  }
  final ctrl = TextEditingController();
  final counted = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ปิดรอบ — นับเงินในลิ้นชัก'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('นับเงินสดจริงในลิ้นชักตอนนี้ แล้วกรอกจำนวน',
              style: TextStyle(fontSize: 13)),
          const Text('ซิงก์บิลออฟไลน์จากทุกเครื่องให้ครบก่อนปิดรอบ'),
          if (check.futureOrderCount > 0)
            Text(
                'นัดรับวันถัดไป ${check.futureOrderCount} ออเดอร์ เก็บไว้ทำต่อได้ เงินที่รับในรอบนี้ยังนับในยอดปิดรอบตามปกติ'),
          if (session.accountingVersion != 1)
            const Text(
                'การยืนยันจะเก็บรอบเก่าเป็น “รอตรวจสอบ” ไม่คำนวณยอดเกิน/ขาดจากข้อมูลที่ไม่ครบ'),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'เงินสดนับได้จริง (บาท)',
                prefixText: '฿',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () {
            final v = double.tryParse(ctrl.text.trim().replaceAll(',', ''));
            if (v == null || !v.isFinite || v < 0) return;
            Navigator.pop(ctx, v);
          },
          child: const Text('ปิดรอบ'),
        ),
      ],
    ),
  );
  if (counted == null) return;
  final staff = await StaffService.getActive();
  if (!context.mounted) return;
  SessionSummary? result;
  CashSession? closedSession;
  final ok = await performShopOperation(context, () async {
    closedSession = await CashSessionService.close(session,
        countedCash: counted,
        closedBy: staff?.name,
        acknowledgeLegacy: session.accountingVersion != 1);
    result = closedSession!.summary;
  }, success: 'ปิดรอบแล้ว');
  if (!ok) return;
  if (result == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'เก็บยอดนับจริงของรอบเก่าแล้ว ยังต้องตรวจสอบประวัติเงิน สามารถเปิดรอบใหม่ได้')));
    }
    return;
  }
  final summary = result!;
  if (!context.mounted) return;

  // Another terminal may have closed this session first. Show the saved count.
  final savedCounted = closedSession!.countedCash ?? counted;
  final overShort = summary.overShort(savedCounted);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ปิดรอบแล้ว'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sumRow('ยอดขายสุทธิในรอบ', '฿${_baht.format(summary.grossTotal)}'),
          _sumRow('รับชำระหนี้', '฿${_baht.format(summary.debtCollections)}'),
          if (summary.futureOrderCount > 0)
            Text(
                'นัดรับวันถัดไป ${summary.futureOrderCount} ออเดอร์ เก็บไว้ทำต่อ เงินที่รับแล้วรวมตามรอบที่รับเงิน'),
          if (summary.pendingOrderCount > 0 || summary.openTableCount > 0)
            Text(
                'ยังไม่รวมออเดอร์รอชำระ ${summary.pendingOrderCount} รายการ และบิลโต๊ะที่ยังเปิด ${summary.openTableCount} บิล'),
          _sumRow('เงินสดควรมี', '฿${_baht.format(summary.expectedCash)}'),
          _sumRow('นับได้จริง', '฿${_baht.format(savedCounted)}'),
          const Divider(),
          _sumRow(
            overShort >= 0 ? 'เกิน' : 'ขาด',
            '฿${_baht.format(overShort.abs())}',
            color: overShort == 0
                ? null
                : (overShort > 0 ? Colors.green : Colors.red),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('ปิด')),
        FilledButton.icon(
          icon: const Icon(Icons.print_outlined, size: 18),
          label: const Text('พิมพ์ Z-report'),
          onPressed: () async {
            Navigator.pop(ctx);
            await ZReportGenerator.print(
                session: closedSession!,
                summary: summary,
                countedCash: savedCounted);
          },
        ),
      ],
    ),
  );
}

Widget _sumRow(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.session});
  final CashSession session;

  @override
  Widget build(BuildContext context) {
    final s = session.summary;
    final counted = session.countedCash ?? 0;
    final over = s != null ? s.overShort(counted) : 0.0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(session.closedAt != null
          ? _dt.format(session.closedAt!)
          : _dt.format(session.openedAt)),
      subtitle: Text(s == null
          ? (session.needsReconciliation
              ? 'รอตรวจสอบ · นับจริง ฿${_baht.format(counted)}'
              : 'ไม่มีสรุปยอด')
          : 'ขาย ฿${_baht.format(s.grossTotal)} · ${s.billCount} บิล · '
              '${over == 0 ? 'ตรง' : over > 0 ? 'เกิน ฿${_baht.format(over)}' : 'ขาด ฿${_baht.format(over.abs())}'}'),
      trailing: s == null
          ? null
          : IconButton(
              icon: const Icon(Icons.print_outlined, size: 20),
              onPressed: () => ZReportGenerator.print(
                  session: session, summary: s, countedCash: counted),
            ),
    );
  }
}
