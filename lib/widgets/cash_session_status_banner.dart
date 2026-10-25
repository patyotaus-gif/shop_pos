import 'package:flutter/material.dart';
import '../models/cash_session.dart';
import '../services/cash_session_service.dart';
import '../screens/cash_session_screen.dart';

class CashSessionStatusBanner extends StatefulWidget {
  const CashSessionStatusBanner({super.key});
  @override
  State<CashSessionStatusBanner> createState() =>
      _CashSessionStatusBannerState();
}

class _CashSessionStatusBannerState extends State<CashSessionStatusBanner> {
  late final _enabled = CashSessionService.watchAccountingEnabled();
  late final _open = CashSessionService.watchOpen();
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
      stream: _enabled,
      builder: (context, enabled) {
        if (enabled.hasError) {
          return const CashSessionNotice(message: 'ตรวจสถานะรอบขายไม่สำเร็จ');
        }
        if (enabled.data != true) return const SizedBox.shrink();
        return StreamBuilder<CashSession?>(
            stream: _open,
            builder: (context, snap) {
              if (snap.hasError) {
                return const CashSessionNotice(
                    message: 'ตรวจสถานะรอบขายไม่สำเร็จ');
              }
              if (snap.connectionState == ConnectionState.waiting ||
                  snap.data != null) {
                return const SizedBox.shrink();
              }
              return CashSessionNotice(
                  message: 'รอบขายปิดอยู่ · เปิดรอบและยืนยันเงินทอนก่อนขาย',
                  onOpen: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const CashSessionScreen())));
            });
      });
}

class CashSessionNotice extends StatelessWidget {
  const CashSessionNotice({super.key, required this.message, this.onOpen});
  final String message;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              const Icon(Icons.pause_circle_outline),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
              if (onOpen != null)
                TextButton(onPressed: onOpen, child: const Text('เปิดรอบ')),
            ])),
      );
}
