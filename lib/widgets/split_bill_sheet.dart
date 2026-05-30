import 'package:flutter/material.dart';

/// Bottom sheet for splitting a table bill evenly across N people.
/// Returns the chosen split count (>= 2) or null on cancel.
///
/// PR 4 supports equal-split only — covers the 80% case (group dinner, bill
/// divided evenly). Custom by-item and uneven splits are out of scope here
/// and can land in a follow-up.
Future<int?> showSplitBillSheet(
  BuildContext context, {
  required double total,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SplitBillSheet(total: total),
  );
}

class _SplitBillSheet extends StatefulWidget {
  const _SplitBillSheet({required this.total});
  final double total;

  @override
  State<_SplitBillSheet> createState() => _SplitBillSheetState();
}

class _SplitBillSheetState extends State<_SplitBillSheet> {
  int _splitCount = 2;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final perPerson = widget.total / _splitCount;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Text('แยกบิล',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ยอดรวม ฿${widget.total.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  const Text('แยกกี่คน?',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  // Quick-pick chips for the common cases — most splits are 2–6
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final n in [2, 3, 4, 5, 6])
                        ChoiceChip(
                          label: Text('$n คน'),
                          selected: _splitCount == n,
                          onSelected: (_) {
                            setState(() {
                              _splitCount = n;
                              _customCtrl.clear();
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('หรือใส่จำนวนคน:',
                          style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _customCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '7+',
                            isDense: true,
                            border: OutlineInputBorder(),
                            suffixText: 'คน',
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null && n >= 2 && n <= 99) {
                              setState(() => _splitCount = n);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline, color: cs.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('แยก $_splitCount คน',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: cs.onSurface
                                          .withValues(alpha: 0.7))),
                              Text(
                                'คนละ ฿${perPerson.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: cs.primary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, _splitCount),
                      icon: const Icon(Icons.check),
                      label: const Text('ไปจ่ายเงิน'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
