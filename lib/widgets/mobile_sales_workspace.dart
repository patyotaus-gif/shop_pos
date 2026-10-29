import 'package:flutter/material.dart';
import '../utils/money_format.dart';

/// One persistent product browser and cart; no extra modal for short phones.
class MobileSalesWorkspace extends StatefulWidget {
  const MobileSalesWorkspace(
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
  State<MobileSalesWorkspace> createState() => _MobileSalesWorkspaceState();
}

class _MobileSalesWorkspaceState extends State<MobileSalesWorkspace> {
  bool _cart = false;

  @override
  void didUpdateWidget(covariant MobileSalesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount > 0 && widget.itemCount == 0) _cart = false;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
            child: IndexedStack(index: _cart ? 1 : 0, children: [
          widget.catalog,
          NestedScrollView(
            headerSliverBuilder: (context, innerScrolled) => [
              SliverToBoxAdapter(
                  child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _cart = false),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('เลือกสินค้าต่อ'),
                ),
              )),
            ],
            body: widget.basket,
          ),
        ])),
        // Checkout belongs to the viewport, never to a taller scrolling cart.
        if (_cart) widget.checkout,
        if (!_cart)
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _cart = true);
                          },
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: Text(
                              'ตะกร้า ${widget.itemCount} หน่วย · ${formatBaht(widget.total)}'))))),
      ]);
}
