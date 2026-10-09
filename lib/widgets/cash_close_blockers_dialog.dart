import 'package:flutter/material.dart';
import '../models/cash_close_check.dart';

enum CashCloseDestination { orders, tables, money }

class CashCloseBlockersDialog extends StatelessWidget {
  const CashCloseBlockersDialog({super.key, required this.check});
  final CashCloseCheck check;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(check.closed ? 'รอบนี้ปิดไปแล้ว' : 'ยังปิดยอดไม่ได้'),
        scrollable: true,
        content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.closed
                    ? 'กลับไปตรวจประวัติรอบขายได้เลย'
                    : 'มี ${check.issueCount} รายการที่ต้องจัดการก่อนปิดยอด ออเดอร์ของวันนี้และวันก่อนต้องเสร็จสิ้น และบิลโต๊ะต้องปิดครบ'),
                if (check.futureOrderCount > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                      'นัดรับวันถัดไป ${check.futureOrderCount} ออเดอร์ เก็บไว้ทำต่อได้ แต่สลิปรอตรวจต้องยืนยันก่อน'),
                ],
                for (final issue in check.issues)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(issue.message),
                    subtitle: Text([
                      if (issue.label.isNotEmpty) issue.label,
                      if (issue.id.isNotEmpty) 'เลขที่ ${issue.id}'
                    ].join('\n')),
                  ),
                if (check.issueCount > check.issues.length)
                  Text(
                      'และอีก ${check.issueCount - check.issues.length} รายการ'),
                if (!check.closed) ...[
                  const SizedBox(height: 8),
                  const Text(
                      'เปิดหน้าที่เกี่ยวข้องเพื่อจัดการ แล้วกลับมาตรวจใหม่'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final entry in const {
                      CashCloseDestination.orders: 'ดูออเดอร์',
                      CashCloseDestination.tables: 'ดูบิลโต๊ะ',
                      CashCloseDestination.money: 'ตรวจรายการเงิน',
                    }.entries)
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, entry.key),
                        child: Text(entry.value),
                      ),
                  ]),
                ],
              ],
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('กลับ'))
        ],
      );
}
