import 'package:flutter/material.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/staff_access_service.dart';
import '../screens/pos_screen.dart';
import '../screens/restaurant_sales_screen.dart';
import '../screens/offline_cash_screen.dart';
import '../utils/operation_error.dart';

/// Use the authenticated staff workspace to select the same selling flow as
/// the owner. Loading/error states must not silently assume a retail shop.
class StaffSalesEntry extends StatefulWidget {
  const StaffSalesEntry(
      {super.key,
      this.loadWorkspace,
      this.restaurant = const RestaurantSalesScreen(),
      this.retail = const PosScreen()});
  final Future<Map<String, dynamic>> Function()? loadWorkspace;
  final Widget restaurant, retail;
  @override
  State<StaffSalesEntry> createState() => _StaffSalesEntryState();
}

class _StaffSalesEntryState extends State<StaffSalesEntry> {
  late Future<Map<String, dynamic>> _workspace = _load();
  Future<Map<String, dynamic>> _load() =>
      (widget.loadWorkspace ?? StaffAccessService.workspace)();
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
      future: _workspace,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(operationError(snapshot.error!),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                            onPressed: () => setState(() {
                                  _workspace = _load();
                                }),
                            icon: const Icon(Icons.refresh),
                            label: const Text('ลองใหม่')),
                        const OfflineEntryButton(),
                      ]))));
        }
        if (!snapshot.hasData) {
          return const Center(
              child: SingleChildScrollView(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              OfflineEntryButton()
            ],
          )));
        }
        final shop = snapshot.data!['shop'] as Map? ?? const {};
        final tier = ShopTier.values.firstWhere((t) => t.name == shop['tier'],
            orElse: () => ShopTier.full);
        final type = ShopType.values.firstWhere(
            (t) => t.name == shop['shopType'],
            orElse: () => ShopType.retail);
        return Entitlements.canUseTables(tier, type)
            ? widget.restaurant
            : widget.retail;
      });
}
