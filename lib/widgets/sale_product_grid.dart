import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_image.dart';

/// Use the catalog's available width, including split-screen and sidebars.
class SaleProductGrid extends StatelessWidget {
  const SaleProductGrid(
      {super.key,
      required this.itemCount,
      required this.itemBuilder,
      this.controller,
      this.footerExtent = 0});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final double footerExtent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        const padding = 12.0;
        const gap = 12.0;
        final available = math.max(1.0, size.maxWidth - padding * 2);
        final columns = size.maxWidth < 300
            ? 1
            : math.max(2, ((available + gap) / (200 + gap)).ceil());
        final width = (available - (columns - 1) * gap) / columns;
        final textScale = MediaQuery.textScalerOf(context);
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: math.min(
                width * 0.78 + textScale.scale(66) + 28 + footerExtent,
                math.max(textScale.scale(66) + 44 + footerExtent,
                    size.maxHeight - padding * 2)),
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      });
}

class SaleProductCard extends StatelessWidget {
  const SaleProductCard(
      {super.key,
      required this.product,
      required this.onTap,
      this.showPromotion = true,
      this.unavailableLabel,
      this.footer});

  final Product product;
  final VoidCallback? onTap;
  // Offline sales use the prepared base price, not live promotions.
  final bool showPromotion;
  final String? unavailableLabel;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final promotion = showPromotion && product.isOnSale;
    final price = showPromotion ? product.effectivePrice : product.price;
    return Tooltip(
      message: product.name,
      child: Card(
        color: cs.surface,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: onTap == null ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: Stack(fit: StackFit.expand, children: [
                  ProductImage(product: product),
                  if (unavailableLabel != null || promotion)
                    Positioned(
                        top: 6,
                        left: 6,
                        right: 6,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                                color: unavailableLabel != null
                                    ? cs.surfaceContainerHighest
                                    : cs.primary,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(
                                unavailableLabel ??
                                    'ลด ${product.discountPercent}%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: unavailableLabel != null
                                        ? cs.onSurface
                                        : cs.onPrimary)),
                          ),
                        )),
                ])),
                Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            height: MediaQuery.textScalerOf(context).scale(40),
                            child: Text(product.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600))),
                        const SizedBox(height: 4),
                        Row(children: [
                          Flexible(
                              child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('฿${price.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary)))),
                          if (promotion) ...[
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text(
                                    '฿${product.price.toStringAsFixed(2)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        decoration: TextDecoration.lineThrough,
                                        color: cs.onSurfaceVariant))),
                          ],
                        ]),
                      ],
                    )),
                if (footer != null) footer!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
