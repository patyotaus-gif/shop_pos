import 'package:flutter/material.dart';
import 'mobile_sales_workspace.dart';

/// Shared by POS and its layout harness; checkout never scrolls with the cart.
class PosSalesWorkspace extends StatefulWidget {
  const PosSalesWorkspace(
      {super.key,
      required this.catalog,
      required this.basket,
      required this.checkout,
      required this.itemCount,
      required this.total});
  final Widget catalog, basket, checkout;
  final num itemCount;
  final double total;

  @override
  State<PosSalesWorkspace> createState() => _PosSalesWorkspaceState();
}

class _PosSalesWorkspaceState extends State<PosSalesWorkspace> {
  // A rotation must not discard a search, scroll or queued category preference.
  final _catalogKey = GlobalKey();

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final catalog = KeyedSubtree(key: _catalogKey, child: widget.catalog);
        if (constraints.maxWidth >= 900) {
          return Row(children: [
            Expanded(child: catalog),
            const VerticalDivider(width: 1),
            SizedBox(
                width: 380,
                child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(children: [
                      Expanded(child: widget.basket),
                      widget.checkout
                    ]))),
          ]);
        }
        return MobileSalesWorkspace(
            itemCount: widget.itemCount,
            total: widget.total,
            catalog: catalog,
            basket: widget.basket,
            checkout: widget.checkout);
      });
}
