/// A display queue belongs to a cash round, not a calendar date or receipt ID.
class RoundQueue {
  final String number;
  final String channel;
  final String sessionId;
  const RoundQueue(this.number, this.channel, this.sessionId);

  String get label => '${channel == 'online' ? 'ออนไลน์' : 'กลับบ้าน'} $number';

  static RoundQueue? fromMap(Map<String, dynamic> data) {
    final number = data['queueNumber'];
    final channel = data['queueChannel'];
    final session = data['queueSessionId'];
    if (number is! String ||
        !RegExp(r'^\d{3,}$').hasMatch(number) ||
        !['online', 'takeaway'].contains(channel) ||
        session is! String ||
        session.isEmpty) {
      return null;
    }
    return RoundQueue(number, channel as String, session);
  }

  Map<String, dynamic> toMap() => {
        'queueNumber': number,
        'queueChannel': channel,
        'queueSessionId': sessionId,
      };
}
