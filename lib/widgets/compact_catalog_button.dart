import 'package:flutter/material.dart';

/// Keep product browsing reachable when keyboard/landscape leaves little room.
class CompactCatalogButton extends StatelessWidget {
  const CompactCatalogButton({super.key, required this.catalog});
  final WidgetBuilder catalog;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      icon: const Icon(Icons.grid_view),
      label: const Text('เลือกสินค้า'),
      onPressed: () {
        FocusScope.of(context).unfocus();
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (ctx) => SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.85,
                child: Column(children: [
                  const ListTile(title: Text('แตะสินค้าเพื่อเพิ่มลงตะกร้า')),
                  Expanded(child: catalog(ctx)),
                  SafeArea(
                      top: false,
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: FilledButton.icon(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.shopping_cart),
                              label: const Text('ดูตะกร้า')))),
                ])));
      });
}
