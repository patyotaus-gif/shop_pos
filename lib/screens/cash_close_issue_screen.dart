import '../widgets/content_width.dart';
import 'package:flutter/material.dart';
import '../models/cash_close_check.dart';
import '../models/table_order.dart';
import '../services/shop_database.dart';
import '../services/auth_service.dart';
import '../services/staff_access_service.dart';
import 'orders_screen.dart';
import 'table_detail_screen.dart';
import 'money_movements_screen.dart';

class CashCloseIssueScreen extends StatefulWidget {
  const CashCloseIssueScreen(
      {super.key, required this.issue, this.tableRecords});
  final CashCloseIssue issue;
  final Stream<Map<String, dynamic>?>? tableRecords;
  @override
  State<CashCloseIssueScreen> createState() => _CashCloseIssueScreenState();
}

class _CashCloseIssueScreenState extends State<CashCloseIssueScreen> {
  late Stream<Map<String, dynamic>?> _records;
  TableOrder? _lastOrder;
  Object? _recordError;

  Stream<Map<String, dynamic>?> _watchTable() {
    if (widget.issue.type != 'openTable') return const Stream.empty();
    return widget.tableRecords ??
        (AuthService.isStaff
            ? StaffAccessService.watchRecord('tableOrders', widget.issue.id)
            : ShopDatabase.shop
                .collection('tableOrders')
                .doc(widget.issue.id)
                .snapshots()
                .map((d) => d.data()));
  }

  @override
  void initState() {
    super.initState();
    _records = _watchTable();
  }

  @override
  void didUpdateWidget(covariant CashCloseIssueScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.issue.id != widget.issue.id ||
        oldWidget.issue.type != widget.issue.type ||
        oldWidget.tableRecords != widget.tableRecords) {
      _lastOrder = null;
      _recordError = null;
      _records = _watchTable();
    }
  }

  Widget _retryButton() => TextButton(
      onPressed: () => setState(() => _records = _watchTable()),
      child: const Text('โหลดไม่ได้ · ลองใหม่'));

  @override
  Widget build(BuildContext context) {
    if (['pendingOrder', 'unfinishedOrder', 'unreviewedPayment']
        .contains(widget.issue.type)) {
      return OrderDetailScreen(orderId: widget.issue.id);
    }
    if (widget.issue.type != 'openTable') {
      if (AuthService.isStaff) {
        return Scaffold(
            appBar: AppBar(title: const Text('ตรวจยอดก่อนปิดรอบ')),
            body: ContentWidth(
                maxWidth: 1040,
                child: const Center(
                    child: Text(
                        'รายการเงินต้องให้เจ้าของร้านตรวจสอบก่อนปิดรอบ'))));
      }
      return MoneyMovementsScreen(
          initialMovementId: widget.issue.type == 'unassignedMovement'
              ? widget.issue.id
              : null);
    }
    return Scaffold(
        appBar: AppBar(title: Text(widget.issue.label)),
        body: ContentWidth(
            maxWidth: 1040,
            child: StreamBuilder<Map<String, dynamic>?>(
                stream: _records,
                builder: (context, snap) {
                  if (snap.hasError) {
                    _recordError = snap.error;
                  } else if (snap.connectionState != ConnectionState.waiting) {
                    _recordError = null;
                    _lastOrder = snap.data?['status'] != 'open'
                        ? null
                        : TableOrder.fromFirestore(snap.data!, widget.issue.id);
                  }
                  if (_lastOrder == null && _recordError != null) {
                    return Center(child: _retryButton());
                  }
                  if (_lastOrder == null &&
                      snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final order = _lastOrder;
                  if (order == null || order.status != TableOrderStatus.open) {
                    return const Center(
                        child: Text('บิลนี้ไม่ค้างแล้ว กลับไปตรวจปิดยอดได้'));
                  }
                  // Keep the callback owner mounted while a poll reconnects.
                  // The catalog's existing session guard blocks writes on error.
                  return Column(children: [
                    if (_recordError != null) _retryButton(),
                    Expanded(
                        child: AbsorbPointer(
                      absorbing: _recordError != null,
                      child: TableOrderView(
                          key: ValueKey(order.id),
                          order: order,
                          orderError: _recordError),
                    )),
                  ]);
                })));
  }
}
