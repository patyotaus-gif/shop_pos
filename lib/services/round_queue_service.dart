import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/round_queue.dart';

class RoundQueueService {
  /// Reads are performed before checkout writes; numbering commits with the sale.
  static Future<RoundQueue?> prepare(
      Transaction tx,
      DocumentReference<Map<String, dynamic>> shop,
      Map<String, dynamic> control,
      DateTime occurredAt) async {
    final id = control['sessionId'] as String?;
    final openedAt = (control['openedAt'] as Timestamp?)?.toDate();
    if (id == null || (openedAt != null && occurredAt.isBefore(openedAt))) {
      return null;
    }
    final session = await tx.get(shop.collection('cashSessions').doc(id));
    if (session.data()?['status'] != 'open') return null;
    final counter =
        await tx.get(shop.collection('counters').doc('queue-$id-takeaway'));
    final previous = counter.data()?['seq'] ?? 0;
    if (previous is! int || previous < 0 || previous >= 9007199254740990) {
      throw StateError('เลขคิวของรอบไม่ถูกต้อง กรุณาติดต่อผู้ดูแล');
    }
    return RoundQueue(
        (previous + 1).toString().padLeft(3, '0'), 'takeaway', id);
  }

  static void write(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, RoundQueue? queue) {
    if (queue == null) return;
    tx.set(
        shop
            .collection('counters')
            .doc('queue-${queue.sessionId}-${queue.channel}'),
        {
          'seq': int.parse(queue.number),
          'sessionId': queue.sessionId,
          'channel': queue.channel,
        });
  }
}
