import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../widgets/sales_channel_scope.dart';
import 'pos_screen.dart';
import 'tables_screen.dart';

/// Create workflows on first visit and keep their state when switching.
class RestaurantSalesScreen extends StatefulWidget {
  const RestaurantSalesScreen(
      {super.key,
      this.dineIn = const TablesScreen(),
      this.takeaway = const PosScreen(initialChannel: SalesChannel.takeaway)});
  final Widget dineIn, takeaway;
  @override
  State<RestaurantSalesScreen> createState() => _RestaurantSalesScreenState();
}

class _RestaurantSalesScreenState extends State<RestaurantSalesScreen> {
  int _mode = 0;
  final _visited = <int>{};

  void _choose() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _mode = 0);
  }

  void _open(int mode) => setState(() {
        _visited.add(mode);
        _mode = mode;
      });

  @override
  Widget build(BuildContext context) => SalesChannelScope(
        choose: _choose,
        child: IndexedStack(index: _mode, children: [
          Scaffold(
            appBar: AppBar(title: const Text('ขายสินค้า')),
            body: SafeArea(
                child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('เลือกรูปแบบการขาย',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 24),
                        LayoutBuilder(builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 560 &&
                              MediaQuery.textScalerOf(context).scale(16) <= 24;
                          final choices = [
                            _choice(context, 1, Icons.restaurant, 'ทานที่ร้าน',
                                'เลือกโต๊ะและรับออเดอร์'),
                            _choice(context, 2, Icons.takeout_dining,
                                'สั่งกลับบ้าน', 'เลือกสินค้าและชำระเงิน'),
                          ];
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Expanded(child: choices[0]),
                                      const SizedBox(width: 16),
                                      Expanded(child: choices[1])
                                    ])
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                      choices[0],
                                      const SizedBox(height: 16),
                                      choices[1]
                                    ]);
                        }),
                      ]))),
            )),
          ),
          _visited.contains(1) ? widget.dineIn : const SizedBox.shrink(),
          _visited.contains(2) ? widget.takeaway : const SizedBox.shrink(),
        ]),
      );

  Widget _choice(BuildContext context, int mode, IconData icon, String title,
          String description) =>
      OutlinedButton(
        key: ValueKey('sales-channel-$mode'),
        onPressed: () => _open(mode),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 36),
          const SizedBox(height: 12),
          Text(title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ]),
      );
}
