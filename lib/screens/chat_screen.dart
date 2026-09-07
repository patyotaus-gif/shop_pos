import 'package:flutter/material.dart';
import '../services/ai_service.dart';
import 'sales_analysis_screen.dart';

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

  int _days = 30;
  String? _usage;
  void _openReport([Map<String, dynamic>? report]) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SalesAnalysisScreen(days: _days, initial: report)));
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _loading || text.length > 4000) return;
    _ctrl.clear();

    setState(() {
      _history.add(AiMessage(role: 'user', content: text));
      _loading = true;
    });
    _scrollDown();

    try {
      final result = await AiService.chat(_history, days: _days);
      if (!mounted) return;
      setState(() {
        _history.add(AiMessage(
            role: 'assistant',
            content: result.reply,
            analysis: result.analysis));
        _usage =
            '${result.dailyCount}/${result.dailyLimit} ครั้งวันนี้ (รอบ UTC)';
        _loading = false;
      });
      _scrollDown();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history.add(AiMessage(
            role: 'assistant', content: 'เกิดข้อผิดพลาด: $e', isError: true));
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
        title: const Text('ผู้ช่วยร้าน Pokpok'),
        centerTitle: true,
        actions: [
          IconButton(
              tooltip: 'เปิดรายงานตัวเลข',
              onPressed: () => _openReport(),
              icon: const Icon(Icons.analytics_outlined))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'AI อธิบายตัวเลขจากบิลร้าน · เปิดรายงานเพื่อตรวจสอบได้',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
          Wrap(spacing: 8, alignment: WrapAlignment.center, children: [
            for (final days in [7, 30, 90])
              ChoiceChip(
                  label: Text('$days วัน'),
                  selected: _days == days,
                  onSelected: _loading
                      ? null
                      : (_) => setState(() {
                            _days = days;
                            _history.clear();
                          })),
            TextButton.icon(
                onPressed: () => _openReport(),
                icon: const Icon(Icons.bar_chart),
                label: const Text('ดูรายงาน')),
          ]),
          Text('เทียบช่วงที่จบแล้ว · เปลี่ยนช่วงเริ่มบทสนทนาใหม่',
              style: Theme.of(context).textTheme.bodySmall),
          if (_usage != null)
            Text(_usage!, style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: _history.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome,
                              size: 64,
                              color: cs.primary.withValues(alpha: 0.4)),
                          const SizedBox(height: 12),
                          Text(
                              'ดูว่ายอดเปลี่ยนจากอะไร สินค้าไหนขายดี\nและกำไรส่วนไหนมีข้อมูลครบ',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant)),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              'สรุปยอดขายเทียบช่วงก่อนให้หน่อย',
                              'สินค้าอะไรทำให้ยอดเปลี่ยนมากที่สุด?',
                              'สินค้าขายดีตัวไหนกำไรน้อย?',
                            ]
                                .map((q) => ActionChip(
                                      label: Text(q,
                                          style: const TextStyle(fontSize: 12)),
                                      onPressed: () {
                                        _ctrl.text = q;
                                        _send();
                                      },
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
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
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('กำลังคิด...',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }
                      final msg = _history[i];
                      final isUser = msg.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color:
                                isUser ? cs.primary : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomRight:
                                  isUser ? const Radius.circular(4) : null,
                              bottomLeft:
                                  !isUser ? const Radius.circular(4) : null,
                            ),
                          ),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  msg.content,
                                  style: TextStyle(
                                    color: isUser ? cs.onPrimary : cs.onSurface,
                                    fontSize: 14,
                                  ),
                                ),
                                if (msg.analysis != null)
                                  TextButton.icon(
                                      onPressed: () =>
                                          _openReport(msg.analysis),
                                      icon: const Icon(Icons.receipt_long),
                                      label: const Text(
                                          'ดูตัวเลขและบิลที่ใช้ตอบ')),
                              ]),
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
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 4000,
                    decoration: InputDecoration(
                      hintText: 'วันนี้อยากให้ช่วยดูอะไร?',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'ส่งคำถาม',
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
