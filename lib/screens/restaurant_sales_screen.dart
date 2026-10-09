import 'package:flutter/material.dart';
import '../models/sale.dart';
import 'pos_screen.dart';
import 'tables_screen.dart';

/// Keep both workflows mounted so switching does not discard a counter cart.
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
  @override
  Widget build(BuildContext context) => SafeArea(
      bottom: false,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.restaurant),
                      label: Text('กินที่ร้าน')),
                  ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.takeout_dining),
                      label: Text('กลับบ้าน')),
                ],
                selected: {
                  _mode
                },
                onSelectionChanged: (value) =>
                    setState(() => _mode = value.first))),
        Expanded(
            child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: IndexedStack(index: _mode, children: [
                  widget.dineIn,
                  widget.takeaway,
                ]))),
      ]));
}
