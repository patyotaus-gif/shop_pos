import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Founder-only business dashboard — MRR/ARR, active vs trial vs expired
/// shops, tier mix, growth and a rough trial→paid conversion. Backed by
/// the `opsMetrics` Cloud Function (admin SDK, founder-email gated), so the
/// client never reads other shops directly and Firestore rules stay
/// per-owner.
class OpsDashboardScreen extends StatefulWidget {
  const OpsDashboardScreen({super.key});

  @override
  State<OpsDashboardScreen> createState() => _OpsDashboardScreenState();
}

class _OpsDashboardScreenState extends State<OpsDashboardScreen> {
  static final _num = NumberFormat('#,##0', 'th_TH');
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('opsMetrics');
    final res = await fn.call();
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภาพรวมธุรกิจ'), centerTitle: true),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(
              message: snap.error.toString(),
              onRetry: _refresh,
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: _Body(metrics: snap.data!, fmt: _num),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.metrics, required this.fmt});

  final Map<String, dynamic> metrics;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final totals = Map<String, dynamic>.from(metrics['totals'] ?? {});
    final growth = Map<String, dynamic>.from(metrics['growth'] ?? {});
    final trials = Map<String, dynamic>.from(metrics['trials'] ?? {});
    final tierAll = Map<String, dynamic>.from(metrics['tierAll'] ?? {});
    final tierPaid = Map<String, dynamic>.from(metrics['tierPaid'] ?? {});

    final mrr = (metrics['mrr'] ?? 0) as num;
    final arr = (metrics['arr'] ?? 0) as num;
    final arpa = (metrics['arpa'] ?? 0) as num;
    final conversion = (metrics['conversionRate'] ?? 0) as num;
    final referred = (metrics['referredCount'] ?? 0) as num;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _MrrHero(mrr: mrr, arr: arr, fmt: fmt),
        const SizedBox(height: 16),
        _StatGrid(children: [
          _Stat(label: 'ร้านทั้งหมด', value: fmt.format(totals['total'] ?? 0)),
          _Stat(
              label: 'จ่ายเงินแล้ว',
              value: fmt.format(totals['active'] ?? 0),
              accent: true),
          _Stat(label: 'ทดลองใช้', value: fmt.format(totals['trialing'] ?? 0)),
          _Stat(label: 'หมดอายุ', value: fmt.format(totals['expired'] ?? 0)),
        ]),
        const SizedBox(height: 16),
        _StatGrid(children: [
          _Stat(label: 'รายได้เฉลี่ย/ร้าน', value: '฿${fmt.format(arpa)}'),
          _Stat(
              label: 'Conversion (ประมาณ)',
              value: '${conversion.toStringAsFixed(1)}%'),
          _Stat(label: 'สมัครใหม่ 7 วัน', value: fmt.format(growth['new7'] ?? 0)),
          _Stat(
              label: 'สมัครใหม่ 30 วัน',
              value: fmt.format(growth['new30'] ?? 0)),
        ]),
        const SizedBox(height: 24),
        _SectionLabel('สัดส่วนตามแพ็กเกจ'),
        const SizedBox(height: 8),
        _TierTable(tierAll: tierAll, tierPaid: tierPaid, fmt: fmt),
        const SizedBox(height: 24),
        _SectionLabel('ทดลองใช้ & แนะนำเพื่อน'),
        const SizedBox(height: 8),
        _MiniRow(
          icon: Icons.timer_outlined,
          label: 'ทดลองใกล้หมด (ภายใน 7 วัน)',
          value: fmt.format(trials['endingSoon'] ?? 0),
        ),
        _MiniRow(
          icon: Icons.handshake_outlined,
          label: 'ร้านที่มาจากการแนะนำ',
          value: fmt.format(referred),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'อัปเดต ${_formatTime(metrics['generatedAt'])}',
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.45)),
          ),
        ),
      ],
    );
  }

  String _formatTime(Object? iso) {
    if (iso is! String) return '-';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '-';
    return DateFormat('d MMM yyyy HH:mm', 'th_TH').format(dt);
  }
}

class _MrrHero extends StatelessWidget {
  const _MrrHero({required this.mrr, required this.arr, required this.fmt});

  final num mrr;
  final num arr;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MRR · รายได้ประจำต่อเดือน',
              style: TextStyle(
                  color: cs.onPrimary.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('฿${fmt.format(mrr)}',
              style: TextStyle(
                  color: cs.onPrimary,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  height: 1.1)),
          const SizedBox(height: 8),
          Text('ARR ฿${fmt.format(arr)} / ปี',
              style: TextStyle(
                  color: cs.onPrimary.withValues(alpha: 0.85),
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.1,
      children: children,
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: accent ? cs.primary : cs.onSurface)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _TierTable extends StatelessWidget {
  const _TierTable(
      {required this.tierAll, required this.tierPaid, required this.fmt});

  final Map<String, dynamic> tierAll;
  final Map<String, dynamic> tierPaid;
  final NumberFormat fmt;

  static const _labels = {
    'solo': 'Solo',
    'lite': 'Lite',
    'full': 'Full',
    'restaurant': 'Restaurant',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(child: SizedBox()),
                _head('ทั้งหมด', cs),
                _head('จ่ายแล้ว', cs),
              ],
            ),
          ),
          for (final key in _labels.keys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_labels[key]!,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  _cell(fmt.format(tierAll[key] ?? 0), cs),
                  _cell(fmt.format(tierPaid[key] ?? 0), cs, accent: true),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _head(String t, ColorScheme cs) => SizedBox(
        width: 72,
        child: Text(t,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.6))),
      );

  Widget _cell(String t, ColorScheme cs, {bool accent = false}) => SizedBox(
        width: 72,
        child: Text(t,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accent ? cs.primary : cs.onSurface)),
      );
}

class _MiniRow extends StatelessWidget {
  const _MiniRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final denied = message.contains('permission-denied') ||
        message.contains('Founder only');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(denied ? Icons.lock_outline : Icons.error_outline,
                size: 48, color: cs.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'หน้านี้สำหรับผู้ดูแลระบบเท่านั้น'
                  : 'โหลดข้อมูลไม่สำเร็จ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            if (!denied)
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('ลองใหม่'),
              ),
          ],
        ),
      ),
    );
  }
}
