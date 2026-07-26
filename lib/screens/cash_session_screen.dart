import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/cash_session.dart';
import '../services/cash_session_service.dart';
import '../services/staff_service.dart';
import '../utils/zreport_generator.dart';

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
          final open = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                  final list = (hs.data ?? const [])
                      .where((s) => s.closed)
                      .toList();
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
  final ctrl = TextEditingController(text: '0');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('เปิดรอบ'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
            labelText: 'เงินทอนเริ่มต้นในลิ้นชัก (บาท)',
            prefixText: '฿',
            border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เปิดรอบ')),
      ],
    ),
  );
  if (ok != true) return;
  final float = double.tryParse(ctrl.text.trim().replaceAll(',', '')) ?? 0;
  final staff = await StaffService.getActive();
  await CashSessionService.open(openingFloat: float, openedBy: staff?.name);
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
  final ctrl = TextEditingController();
  final counted = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ปิดรอบ — นับเงินในลิ้นชัก'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('นับเงินสดจริงในลิ้นชักตอนนี้ แล้วกรอกจำนวน',
              style: TextStyle(fontSize: 13)),
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
            if (v == null) return;
            Navigator.pop(ctx, v);
          },
          child: const Text('ปิดรอบ'),
        ),
      ],
    ),
  );
  if (counted == null) return;
  final staff = await StaffService.getActive();
  final summary = await CashSessionService.close(session,
      countedCash: counted, closedBy: staff?.name);
  if (!context.mounted) return;

  final overShort = summary.overShort(counted);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ปิดรอบแล้ว'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sumRow('ยอดขายรวม', '฿${_baht.format(summary.grossTotal)}'),
          _sumRow('เงินสดควรมี', '฿${_baht.format(summary.expectedCash)}'),
          _sumRow('นับได้จริง', '฿${_baht.format(counted)}'),
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
                session: session, summary: summary, countedCash: counted);
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
          ? '—'
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
