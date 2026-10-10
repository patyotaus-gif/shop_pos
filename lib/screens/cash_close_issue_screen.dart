import 'package:flutter/material.dart';
import '../models/cash_close_check.dart';
import '../models/table_order.dart';
import '../services/shop_database.dart';
import 'orders_screen.dart';
import 'table_detail_screen.dart';
import 'money_movements_screen.dart';

class CashCloseIssueScreen extends StatefulWidget {
  const CashCloseIssueScreen({super.key, required this.issue});
  final CashCloseIssue issue;
  @override
  State<CashCloseIssueScreen> createState() => _CashCloseIssueScreenState();
}

class _CashCloseIssueScreenState extends State<CashCloseIssueScreen> {
  int _retry = 0;
  @override
  Widget build(BuildContext context) {
    if (['pendingOrder', 'unfinishedOrder', 'unreviewedPayment']
        .contains(widget.issue.type)) {
      return OrderDetailScreen(orderId: widget.issue.id);
    }
    if (widget.issue.type != 'openTable') {
      return MoneyMovementsScreen(
          initialMovementId: widget.issue.type == 'unassignedMovement'
              ? widget.issue.id
              : null);
    }
    return Scaffold(
        appBar: AppBar(title: Text(widget.issue.label)),
        body: StreamBuilder(
            key: ValueKey(_retry),
            stream: ShopDatabase.shop
                .collection('tableOrders')
                .doc(widget.issue.id)
                .snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                    child: TextButton(
                        onPressed: () => setState(() => _retry++),
                        child: const Text('โหลดไม่ได้ · ลองใหม่')));
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data!.data();
              if (data == null || data['status'] != 'open') {
                return const Center(
                    child: Text('บิลนี้ไม่ค้างแล้ว กลับไปตรวจปิดยอดได้'));
              }
              return TableOrderView(
                  order: TableOrder.fromFirestore(data, snap.data!.id));
            }));
  }
}
