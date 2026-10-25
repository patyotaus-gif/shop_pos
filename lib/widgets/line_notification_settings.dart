import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/line_service.dart';
import 'compact_action.dart';

class LineNotificationSettings extends StatelessWidget {
  const LineNotificationSettings(
      {super.key,
      required this.controller,
      required this.enabled,
      required this.saving,
      required this.onEnabledChanged,
      required this.onSave,
      required this.onTest,
      required this.onOpenLine});
  final TextEditingController controller;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onEnabledChanged;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onOpenLine;

  @override
  Widget build(BuildContext context) => ExpansionTile(
          // Expansion state is a bool; descendant scroll offsets are doubles.
          // Give both the tile and field distinct PageStorage paths.
          key: const PageStorageKey('line-manual-settings'),
          title: const Text('ตั้งค่าการแจ้งเตือน / เชื่อมด้วยรหัสเอง'),
          children: [
            // LINE Notification section
            Text('การแจ้งเตือน LINE',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF06C755).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF06C755).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. สแกน QR หรือกดเปิด LINE Pokpok ด้านล่าง แล้วเพิ่มเพื่อน\n2. ส่งคำว่า ID ในแชต Pokpok\n3. คัดลอกรหัสที่ขึ้นต้นด้วย U มาวางด้านล่าง\n4. เปิดแจ้งเตือน แล้วกดทดสอบ\nรหัสนี้ไม่ใช่ LINE ID ที่คุณตั้งเอง',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('สแกนเพื่อเพิ่มเพื่อน LINE Pokpok',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Center(
              child: Semantics(
                label:
                    'QR เพิ่มเพื่อน LINE Pokpok ใช้ลิงก์เดียวกับปุ่มเปิด LINE',
                image: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: QrImageView(
                      data: LineService.officialAccountUrl,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
                'ใช้มือถือสแกนจากแท็บเล็ตหรือเครื่อง POS หากใช้เครื่องเดียวกันให้กดปุ่มด้านล่าง',
                textAlign: TextAlign.center),
            OutlinedButton.icon(
                onPressed: onOpenLine,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('เปิด LINE Pokpok / เพิ่มเพื่อน')),
            const Text(
                'รับแจ้งเตือนออเดอร์และออเดอร์ค้าง เพื่อช่วยติดตามงานของร้าน'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.notifications_active_outlined,
                  color: Color(0xFF06C755)),
              title: const Text('เปิดแจ้งเตือนผ่าน LINE'),
              value: enabled,
              onChanged: (val) => onEnabledChanged(val),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const PageStorageKey('line-user-id-field'),
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'รหัสเชื่อมต่อจากแชต Pokpok',
                hintText: 'Uxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                prefixIcon:
                    Icon(Icons.chat_bubble_outline, color: Color(0xFF06C755)),
                border: OutlineInputBorder(),
                helperText: 'ส่งคำว่า ID ในแชต Pokpok เพื่อรับรหัส',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            ActionButtons(
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF06C755)),
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined),
                  label: const Text('บันทึก'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : onTest,
                  icon:
                      const Icon(Icons.send_outlined, color: Color(0xFF06C755)),
                  label: const Text('ทดสอบ',
                      style: TextStyle(color: Color(0xFF06C755))),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF06C755))),
                ),
              ],
            ),
          ]);
}
