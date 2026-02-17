class ChatMessage {
  final String sender;
  final String? senderUuid;
  final String message;
  final int timestamp;
  final bool isOutgoing;

  const ChatMessage({
    required this.sender,
    this.senderUuid,
    required this.message,
    required this.timestamp,
    this.isOutgoing = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      sender: json['sender'] as String? ?? 'Unknown',
      senderUuid: json['senderUuid'] as String?,
      message: json['message'] as String? ?? '',
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      isOutgoing: false,
    );
  }
}

class ChatDeniedEvent {
  final String reason;

  const ChatDeniedEvent({required this.reason});

  factory ChatDeniedEvent.fromJson(Map<String, dynamic> json) {
    return ChatDeniedEvent(
      reason: json['reason'] as String? ?? 'Unknown reason',
    );
  }
}

class ChatModeEvent {
  final bool started;

  const ChatModeEvent({required this.started});

  factory ChatModeEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    return ChatModeEvent(started: type == 'CHAT_MODE_STARTED');
  }
}

enum ChatMessageResult {
  allow,
  modify,
  deny,
  pass,
}

typedef ChatMessageListener = ChatMessageResult Function(ChatMessage message);
