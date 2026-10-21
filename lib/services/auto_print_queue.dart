/// One serial consumer. A lost server acknowledgement must retry the result
/// write, never the physical print. The durable claim lives on the server.
class AutoPrintQueue {
  AutoPrintQueue(
      {required this.call,
      required this.send,
      required this.active,
      required this.status,
      this.errorMessage});
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
      call;
  final Future<void> Function(Map<String, dynamic>) send;
  final bool Function() active;
  final Future<void> Function(String) status;
  final String Function(Object)? errorMessage;
  bool _busy = false;
  Map<String, dynamic>? _result;
  bool get hasPendingResult => _result != null;

  Future<void> pump() async {
    if (_busy || !active()) return;
    _busy = true;
    try {
      while (active()) {
        if (_result != null) {
          await call('finishAutoPrint', _result!);
          _result = null;
        }
        final job = await call('claimAutoPrint', {});
        if (job['blocked'] != null) {
          await status('พักคิว • เปิดแอพเพื่อตรวจงานพิมพ์ก่อนหน้า');
          return;
        }
        if (job['empty'] == true) {
          await status('พร้อมรับออเดอร์และพิมพ์อัตโนมัติ');
          return;
        }
        var outcome = 'sent';
        var reason = '';
        try {
          if (!active()) return;
          await send(job);
        } catch (e) {
          outcome = 'needsReview';
          reason = errorMessage?.call(e) ??
              'ส่งงานไม่สำเร็จหรือผลไม่แน่นอน ตรวจเครื่องและกระดาษก่อนลองใหม่';
        }
        _result = {
          'jobId': job['jobId'],
          'attempt': job['attempt'],
          'outcome': outcome,
          'reason': reason
        };
      }
    } finally {
      _busy = false;
    }
  }
}
