import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/staff_access_service.dart';
import '../utils/operation_error.dart';
import 'offline_cash_screen.dart';

class UserSwitchScreen extends StatefulWidget {
  const UserSwitchScreen({super.key, this.loadStaff, this.switchTo});
  final Future<Map<String, dynamic>> Function()? loadStaff;
  final Future<void> Function(String, String)? switchTo;
  @override
  State<UserSwitchScreen> createState() => _UserSwitchScreenState();
}

class _UserSwitchScreenState extends State<UserSwitchScreen> {
  late Future<Map<String, dynamic>> _staff = _load();
  Future<Map<String, dynamic>> _load() =>
      widget.loadStaff?.call() ?? StaffAccessService.call('staffList');
  bool _busy = false;
  String? _error;
  Future<void> _select(Map staff) async {
    final pin = TextEditingController();
    final code = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('PIN ของ ${staff['name']}'),
              content: TextField(
                  controller: pin,
                  obscureText: true,
                  autofocus: true,
                  maxLength: 8,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN 4–8 หลัก'),
                  onSubmitted: (value) => Navigator.pop(ctx, value)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ยกเลิก')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, pin.text),
                    child: const Text('เข้าใช้งาน'))
              ],
            ));
    // Controller belongs to the closing dialog; dispose after its animation.
    Future<void>.delayed(const Duration(seconds: 1), pin.dispose);
    if (code == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.switchTo ?? StaffAccessService.switchTo)(
          staff['id'] as String, code);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _owner() async {
    // Never restore a cached owner credential when leaving staff mode.
    await AuthService.signOut();
    StaffAccessService.unlocked.value = false;
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('เลือกผู้ใช้งาน')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const OfflineEntryButton(),
          const Text(
              'เจ้าของร้านจัดการข้อมูลและสิทธิ์ พนักงานขายและรับเงินได้ แต่ดูรายงาน ต้นทุน ตั้งค่า หรือคืนเงินไม่ได้'),
          const SizedBox(height: 16),
          ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('เจ้าของร้าน'),
              subtitle:
                  const Text('เข้าสู่ระบบด้วยอีเมลและรหัสผ่านเจ้าของร้าน'),
              onTap: _busy ? null : _owner),
          const Divider(),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FutureBuilder<Map<String, dynamic>>(
              future: _staff,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Column(children: [
                    Text(operationError(snap.error!)),
                    TextButton(
                        onPressed: () => setState(() => _staff = _load()),
                        child: const Text('ลองใหม่'))
                  ]);
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final staff = snap.data!['staff'] as List;
                if (staff.isEmpty) {
                  return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'ยังไม่มีพนักงาน เพิ่มได้ที่ ตั้งค่า → พนักงาน ในบัญชีเจ้าของร้าน'));
                }
                return Column(
                    children: staff
                        .map((s) => ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(s['name'] as String),
                            subtitle:
                                const Text('พนักงานขาย · ใช้ PIN เข้าใช้งาน'),
                            onTap: _busy ? null : () => _select(s as Map)))
                        .toList());
              }),
        ]),
      ));
}
