import 'package:flutter/material.dart';
import '../utils/money_format.dart';

/// One persistent product browser and cart; no extra modal for short phones.
class MobileSalesWorkspace extends StatefulWidget {
  const MobileSalesWorkspace(
      {super.key,
      required this.catalog,
      required this.basket,
      required this.itemCount,
      required this.total});
  final Widget catalog, basket;
  final int itemCount;
  final double total;
  @override
  State<MobileSalesWorkspace> createState() => _MobileSalesWorkspaceState();
}

class _MobileSalesWorkspaceState extends State<MobileSalesWorkspace> {
  bool _cart = false;
  final _basketScroll = ScrollController();

  @override
  void dispose() {
    _basketScroll.dispose();
    super.dispose();
  }

  bool _scrollPastBasket(OverscrollNotification notification) {
    // The cart's ListView otherwise consumes the drag at its end, leaving
    // checkout below the viewport on short/landscape phones.
    if (notification.depth > 0 &&
        notification.metrics.axis == Axis.vertical &&
        notification.dragDetails != null &&
        _basketScroll.hasClients) {
      final position = _basketScroll.position;
      _basketScroll.jumpTo((position.pixels + notification.overscroll)
          .clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant MobileSalesWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount > 0 && widget.itemCount == 0) _cart = false;
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_cart)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => setState(() => _cart = false),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('เลือกสินค้าต่อ'))),
        Expanded(
            child: LayoutBuilder(
                builder: (context, constraints) =>
                    IndexedStack(index: _cart ? 1 : 0, children: [
                      widget.catalog,
                      constraints.maxHeight < 340
                          ? NotificationListener<OverscrollNotification>(
                              onNotification: _scrollPastBasket,
                              child: SingleChildScrollView(
                                controller: _basketScroll,
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context)
                                      .copyWith(
                                          physics: const ClampingScrollPhysics(
                                              parent:
                                                  AlwaysScrollableScrollPhysics())),
                                  child: SizedBox(
                                      height: 480, child: widget.basket),
                                ),
                              ))
                          : widget.basket,
                    ]))),
        if (!_cart)
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                          onPressed: () => setState(() => _cart = true),
                          icon: const Icon(Icons.shopping_cart_outlined),
                          label: Text(
                              'ตะกร้า ${widget.itemCount} ชิ้น · ${formatBaht(widget.total)}'))))),
      ]);
}
