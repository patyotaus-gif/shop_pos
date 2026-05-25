import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import '../services/sale_service.dart';
import '../services/product_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _history = [];
  bool _loading = false;

  Future<String> _buildContext() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final sales = await SaleService.watchByRange(start, now).first;
      final products = await ProductService.watchAll().first;
      final lowStock = products.where((p) => p.isLowStock).toList();
      final revenue = sales.fold<double>(0, (s, e) => s + e.total);

      return '''
ยอดขายวันนี้: ฿${revenue.toStringAsFixed(2)} (${sales.length} บิล)
สินค้าใกล้หมด: ${lowStock.isEmpty ? 'ไม่มี' : lowStock.map((p) => '${p.name}(${p.stock})').join(', ')}
สินค้าทั้งหมด: ${products.length} รายการ
''';
    } catch (_) {
      return '';
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    setState(() {
      _history.add(AiMessage(role: 'user', content: text));
      _loading = true;
    });
    _scrollDown();

    try {
      final context = await _buildContext();
      final result = await AiService.chat(_history, shopContext: context);
      setState(() {
        _history.add(AiMessage(role: 'assistant', content: result.reply));
        _loading = false;
      });
      _scrollDown();
    } catch (e) {
      setState(() {
        _history.add(AiMessage(role: 'assistant', content: 'เกิดข้อผิดพลาด: $e'));
        _loading = false;
      });
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI ผู้ช่วยร้าน'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 64, color: cs.primary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('ถามอะไรก็ได้เกี่ยวกับร้านของคุณ',
                            style: TextStyle(color: Colors.grey.shade500)),
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            'วันนี้ขายได้เท่าไร?',
                            'สินค้าไหนควรสั่งเพิ่ม?',
                            'วิเคราะห์ยอดขายให้หน่อย',
                          ].map((q) => ActionChip(
                            label: Text(q, style: const TextStyle(fontSize: 12)),
                            onPressed: () {
                              _ctrl.text = q;
                              _send();
                            },
                          )).toList(),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length + (_loading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _history.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Row(
                            children: [
                              SizedBox(width: 8),
                              SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('กำลังคิด...', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }
                      final msg = _history[i];
                      final isUser = msg.role == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: isUser ? cs.primary : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight: isUser ? const Radius.circular(4) : null,
                              bottomLeft: !isUser ? const Radius.circular(4) : null,
                            ),
                          ),
                          child: Text(
                            msg.content,
                            style: TextStyle(
                              color: isUser ? cs.onPrimary : cs.onSurface,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    onSubmitted: (_) => _send(),
                    maxLines: null,
                    decoration: InputDecoration(
                      hintText: 'ถามเกี่ยวกับร้าน...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
