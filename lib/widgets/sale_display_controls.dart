import 'package:flutter/material.dart';
import '../services/sale_display_service.dart';
import '../theme/sale_button_palette.dart';

class SaleDisplayScope extends InheritedNotifier<SaleDisplayController> {
  const SaleDisplayScope(
      {super.key,
      required SaleDisplayController? controller,
      required super.child})
      : super(notifier: controller);

  static SaleDisplayController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SaleDisplayScope>()?.notifier;
}

class SaleDisplayControls extends StatelessWidget {
  const SaleDisplayControls({super.key, required this.categories});
  final List<String> categories;

  static Future<void> _save(BuildContext context,
      SaleDisplayController controller, SaleDisplaySettings next) async {
    try {
      await controller.save(next);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('บันทึกรูปแบบหน้าขายไม่ได้ กรุณาลองอีกครั้ง'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SaleDisplayScope.of(context);
    if (controller == null) return const SizedBox.shrink();
    final enabled = controller.loaded && !controller.busy;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final mode in SaleDisplayMode.values)
                ChoiceChip(
                  label: Text(mode == SaleDisplayMode.photos
                      ? 'รูปภาพสินค้า'
                      : 'ปุ่มชื่อสินค้า'),
                  selected: controller.value.mode == mode,
                  onSelected: enabled
                      ? (_) => _save(
                          context, controller, controller.value.withMode(mode))
                      : null,
                ),
              if (controller.value.mode == SaleDisplayMode.names)
                OutlinedButton.icon(
                  icon: const Icon(Icons.palette_outlined, size: 18),
                  label: const Text('สีปุ่ม'),
                  onPressed: enabled && categories.isNotEmpty
                      ? () => showDialog<void>(
                            context: context,
                            builder: (_) => _CategoryColors(
                                controller: controller, categories: categories),
                          )
                      : null,
                ),
              if (controller.loadFailed)
                OutlinedButton.icon(
                  onPressed: enabled ? controller.load : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('โหลดรูปแบบอีกครั้ง'),
                ),
            ]),
      ),
    );
  }
}

/// Secondary configuration for the sales workspace.
class SaleDisplayButton extends StatelessWidget {
  const SaleDisplayButton({super.key, required this.categories});
  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    final controller = SaleDisplayScope.of(context);
    if (controller == null) return const SizedBox.shrink();
    return OutlinedButton.icon(
      key: const ValueKey('sale-display-settings'),
      onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => SaleDisplayScope(
              controller: controller,
              child: AlertDialog(
                title: const Text('จัดหน้าขาย'),
                content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                        child: SaleDisplayControls(categories: categories))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('เสร็จ'))
                ],
              ))),
      icon: const Icon(Icons.tune, size: 18),
      label: const Text('จัดหน้าขาย'),
    );
  }
}

class _CategoryColors extends StatefulWidget {
  const _CategoryColors({required this.controller, required this.categories});
  final SaleDisplayController controller;
  final List<String> categories;

  @override
  State<_CategoryColors> createState() => _CategoryColorsState();
}

class _CategoryColorsState extends State<_CategoryColors> {
  late String _category = widget.categories.first;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final selected = controller.value.categoryColors[_category];
          final cs = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Row(children: [
              const Expanded(child: Text('สีปุ่มตามหมวดหมู่')),
              IconButton(
                  tooltip: 'ปิด',
                  onPressed:
                      controller.busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'ใช้กับสินค้าทั้งหมวด บันทึกเฉพาะร้านนี้บนเครื่องนี้'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                    items: widget.categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: controller.busy
                        ? null
                        : (v) => setState(() => _category = v!),
                  ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final color in [
                      null,
                      ...SaleDisplaySettings.colorNames
                    ])
                      ChoiceChip(
                        label: Text(color == null
                            ? 'ค่าเริ่มต้น'
                            : SaleButtonPalette.labels[color]!),
                        selected: selected == color,
                        backgroundColor:
                            SaleButtonPalette.background(context, color),
                        selectedColor:
                            SaleButtonPalette.background(context, color),
                        labelStyle: TextStyle(color: cs.onSurface),
                        checkmarkColor: cs.onSurface,
                        side: BorderSide(
                            color:
                                selected == color ? cs.onSurface : cs.outline),
                        onSelected: controller.busy
                            ? null
                            : (_) => SaleDisplayControls._save(
                                context,
                                controller,
                                controller.value.withColor(_category, color)),
                      ),
                  ]),
                  const SizedBox(height: 16),
                  const Text(
                      'สีช่วยให้หาเมนูได้เร็วขึ้น ชื่อสินค้าและราคายังคงแสดงเสมอ'),
                ],
              )),
            ),
            actions: [
              FilledButton(
                  onPressed:
                      controller.busy ? null : () => Navigator.pop(context),
                  child: const Text('เสร็จแล้ว'))
            ],
          );
        },
      );
}
