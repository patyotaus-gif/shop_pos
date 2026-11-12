import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/product.dart';
import 'product_image.dart';
import '../utils/money_format.dart';
import '../services/sale_display_service.dart';
import '../theme/sale_button_palette.dart';
import 'sale_display_controls.dart';

/// Measure the longest name/category rather than clipping similar menu names.
/// The price, promotion and availability rows keep their own space.
double saleNameTileHeight(
    BuildContext context, double width, List<Product> products,
    {double footerExtent = 0}) {
  final scaler = MediaQuery.textScalerOf(context);
  double measure(String text, double size, FontWeight weight) {
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: DefaultTextStyle.of(context)
              .style
              .copyWith(fontSize: size, height: 1.4, fontWeight: weight)),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout(maxWidth: math.max(1, width - 24));
    final height = painter.height;
    painter.dispose();
    return height;
  }

  double name = scaler.scale(44.8), category = scaler.scale(16.8);
  for (final p in products) {
    name = math.max(name, measure(p.name, 16, FontWeight.w600));
    category = math.max(category, measure(p.category, 12, FontWeight.w400));
  }
  return name + category + scaler.scale(58) + 48 + footerExtent;
}

/// Use the catalog's available width, including split-screen and sidebars.
class SaleProductGrid extends StatelessWidget {
  const SaleProductGrid(
      {super.key,
      required this.itemCount,
      required this.itemBuilder,
      this.controller,
      this.products = const [],
      this.footerExtent = 0});

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;
  final double footerExtent;
  final List<Product> products;

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
        final names =
            SaleDisplayScope.of(context)?.value.mode == SaleDisplayMode.names;
        return GridView.builder(
          controller: controller,
          padding: const EdgeInsets.all(padding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: names
                ? saleNameTileHeight(context, width, products,
                    footerExtent: footerExtent)
                : math.min(
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
      this.selected = false,
      this.unavailableLabel,
      this.footer});

  final Product product;
  final VoidCallback? onTap;
  // Offline sales use the prepared base price, not live promotions.
  final bool showPromotion;
  final bool selected;
  final String? unavailableLabel;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final promotion = showPromotion && product.isOnSale;
    final price = showPromotion ? product.effectivePrice : product.price;
    final display = SaleDisplayScope.of(context)?.value;
    if (display?.mode == SaleDisplayMode.names) {
      return Card(
        color: onTap == null
            ? cs.surfaceContainerHigh
            : SaleButtonPalette.background(
                context, display!.categoryColors[product.category]),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: selected ? cs.primary : cs.outline,
                width: selected ? 2 : 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: Padding(
              padding: const EdgeInsets.all(12),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: cs.onSurface, height: 1.4),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.category,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Expanded(
                          child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(product.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.4,
                                      fontWeight: FontWeight.w600)))),
                      const SizedBox(height: 8),
                      Text(formatBaht(price),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      if (promotion)
                        Text(formatBaht(product.price),
                            style: const TextStyle(
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough)),
                      if (unavailableLabel != null || onTap == null)
                        Row(children: [
                          Icon(
                              onTap == null
                                  ? Icons.block
                                  : selected
                                      ? Icons.check_circle_outline
                                      : Icons.info_outline,
                              size: 16,
                              color: cs.onSurface),
                          const SizedBox(width: 4),
                          Expanded(
                              child: Text(unavailableLabel ?? 'ยังเลือกไม่ได้',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600))),
                        ]),
                    ]),
              ),
            )),
            if (footer != null) footer!,
          ]),
        ),
      );
    }
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
                                    fontSize: 13,
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
                                  child: Text(formatBaht(price),
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: cs.primary)))),
                          if (promotion) ...[
                            const SizedBox(width: 4),
                            Flexible(
                                child: Text(formatBaht(product.price),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12,
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
