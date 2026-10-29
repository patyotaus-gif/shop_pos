import 'package:flutter/material.dart';

/// The heading, items and optional loyalty row share one scroll area. Checkout
/// is rendered separately so short windows never push the payment action away.
class PosBasket extends StatelessWidget {
  const PosBasket(
      {super.key,
      required this.itemCount,
      required this.itemBuilder,
      this.loyalty});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Widget? loyalty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          const Icon(Icons.shopping_cart_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text('รายการขาย',
                  style: Theme.of(context).textTheme.titleMedium)),
          Flexible(child: Text('$itemCount รายการ', textAlign: TextAlign.end)),
        ]),
      )),
      if (itemCount == 0)
        SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 64, color: cs.onSurfaceVariant),
                const SizedBox(height: 8),
                Text('ยังไม่มีสินค้าในตะกร้า',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            )))
      else
        SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverList(
                delegate: SliverChildBuilderDelegate(itemBuilder,
                    childCount: itemCount))),
      if (loyalty != null) SliverToBoxAdapter(child: loyalty!),
    ]);
  }
}
