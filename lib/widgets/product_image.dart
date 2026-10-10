import 'dart:io';
import 'package:flutter/material.dart';
import '../models/product.dart';

/// Product thumbnail that survives cross-device data.
///
/// `imagePath` is a device-local file — it is only valid on the device that
/// created the product. A POS till often shows products photographed on the
/// owner's phone, so the local file is tried first (free, offline) but a
/// missing/corrupt file falls back to the cloud `imageUrl`, and only then to
/// the placeholder icon. Order: local file → network → icon.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final Product product;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  Widget _fallbackIcon(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
        label: 'ไม่มีรูป ${product.name}',
        child: Container(
          width: width,
          height: height,
          color: cs.surfaceContainerLow,
          child: LayoutBuilder(builder: (context, constraints) {
            final spacious = constraints.maxWidth >= 88 &&
                constraints.maxHeight >=
                    MediaQuery.textScalerOf(context).scale(26) + 48;
            final icon = switch (product.category) {
              'เครื่องดื่ม' => Icons.local_drink_outlined,
              'ขนม' => Icons.cookie_outlined,
              'อาหารสด' => Icons.restaurant_outlined,
              'ของใช้' => Icons.shopping_basket_outlined,
              'ยา' => Icons.medication_outlined,
              _ => Icons.inventory_2_outlined,
            };
            return Center(
                child: ExcludeSemantics(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: spacious ? 32 : 24, color: cs.onSurfaceVariant),
              if (spacious) ...[
                const SizedBox(height: 8),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                        product.name.trim().characters.take(3).toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface))),
              ],
            ])));
          }),
        ));
  }

  Widget _network(BuildContext context) {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) return _fallbackIcon(context);
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (ctx, _, __) => _fallbackIcon(ctx),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget img;
    final path = product.imagePath;
    if (path != null) {
      img = Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        // Stale path (created on another device / data cleared) → cloud copy.
        errorBuilder: (ctx, _, __) => _network(ctx),
      );
    } else {
      img = _network(context);
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}
