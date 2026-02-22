class ChatSegment {
  final String text;
  final String? color;
  final bool bold;
  final bool italic;
  final bool underlined;
  final bool strikethrough;
  final bool obfuscated;
  final ClickAction? clickAction;
  final HoverAction? hoverAction;

  const ChatSegment({
    required this.text,
    this.color,
    this.bold = false,
    this.italic = false,
    this.underlined = false,
    this.strikethrough = false,
    this.obfuscated = false,
    this.clickAction,
    this.hoverAction,
  });

  factory ChatSegment.fromJson(Map<String, dynamic> json) {
    ClickAction? clickAction;
    if (json['clickEvent'] != null) {
      final clickJson = json['clickEvent'] as Map<String, dynamic>;
      clickAction = ClickAction(
        action: clickJson['action'] as String? ?? '',
        value: clickJson['value'] as String? ?? '',
      );
    }

    HoverAction? hoverAction;
    if (json['hoverEvent'] != null) {
      final hoverJson = json['hoverEvent'] as Map<String, dynamic>;
      final action = hoverJson['action'] as String? ?? '';
      if (action == 'show_text' && hoverJson['value'] != null) {
        final valueList = hoverJson['value'] as List<dynamic>;
        final segments = valueList
            .map((s) => ChatSegment.fromJson(s as Map<String, dynamic>))
            .toList();
        hoverAction = HoverAction(action: action, segments: segments);
      }
    }

    return ChatSegment(
      text: json['text'] as String? ?? '',
      color: json['color'] as String?,
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underlined: json['underlined'] as bool? ?? false,
      strikethrough: json['strikethrough'] as bool? ?? false,
      obfuscated: json['obfuscated'] as bool? ?? false,
      clickAction: clickAction,
      hoverAction: hoverAction,
    );
  }
}

class ClickAction {
  final String action;
  final String value;

  const ClickAction({required this.action, required this.value});
}

class HoverAction {
  final String action;
  final List<ChatSegment> segments;

  const HoverAction({required this.action, required this.segments});

  String get text => segments.map((s) => s.text).join();
}

class ChatMessage {
  final String sender;
  final String? senderUuid;
  final List<ChatSegment> segments;
  final int timestamp;

  const ChatMessage({
    required this.sender,
    this.senderUuid,
    required this.segments,
    required this.timestamp,
  });

  String get message => segments.map((s) => s.text).join();

  bool get isSystem => sender == 'System';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    List<ChatSegment> segments = [];
    if (json['segments'] != null) {
      final segmentList = json['segments'] as List<dynamic>;
      segments = segmentList
          .map((s) => ChatSegment.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    if (segments.isEmpty && json['message'] != null) {
      segments = [ChatSegment(text: json['message'] as String)];
    }

    return ChatMessage(
      sender: json['sender'] as String? ?? 'Unknown',
      senderUuid: json['senderUuid'] as String?,
      segments: segments,
      timestamp:
          json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
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
