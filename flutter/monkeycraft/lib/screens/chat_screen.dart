import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/services/chat_models.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';
import 'package:url_launcher/url_launcher.dart';

class _SmartQuotesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text
        .replaceAll('"', '"')
        .replaceAll('"', '"')
        .replaceAll(''', "'")
        .replaceAll(''', "'");
    final isAscii = text.codeUnits.every((c) => c >= 32 && c <= 126);
    if (!isAscii) return oldValue;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _RichText extends StatefulWidget {
  final List<ChatSegment> segments;
  final TextStyle baseStyle;
  final StreamProxy? proxy;

  const _RichText({
    required this.segments,
    required this.baseStyle,
    this.proxy,
  });

  @override
  State<_RichText> createState() => _RichTextState();
}

class _RichTextState extends State<_RichText> {
  final Map<String, TapGestureRecognizer> _tapGesturers = {};

  static final Map<String, Color> _mcColors = {
    'black': Color(0xFF000000),
    'dark_blue': Color(0xFF0000AA),
    'dark_green': Color(0xFF00AA00),
    'dark_aqua': Color(0xFF00AAAA),
    'dark_red': Color(0xFFAA0000),
    'dark_purple': Color(0xFFAA00AA),
    'gold': Color(0xFFFFAA00),
    'gray': Color(0xFFAAAAAA),
    'dark_gray': Color(0xFF555555),
    'blue': Color(0xFF5555FF),
    'green': Color(0xFF55FF55),
    'aqua': Color(0xFF55FFFF),
    'red': Color(0xFFFF5555),
    'light_purple': Color(0xFFFF55FF),
    'yellow': Color(0xFFFFFF55),
    'white': Color(0xFFFFFFFF),
  };

  @override
  void dispose() {
    for (final gr in _tapGesturers.values) {
      gr.dispose();
    }
    super.dispose();
  }

  void _handleClick(ClickAction action) {
    switch (action.action) {
      case 'open_url':
        final uri = Uri.tryParse(action.value);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        break;
      case 'run_command':
        widget.proxy?.trySendChatMessage(action.value);
        break;
      case 'suggest_command':
        break;
      case 'copy_to_clipboard':
        Clipboard.setData(ClipboardData(text: action.value));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Copied to clipboard'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();

    final spans = <InlineSpan>[];
    for (int i = 0; i < widget.segments.length; i++) {
      final seg = widget.segments[i];
      Color? color;
      if (seg.color != null) {
        color = _mcColors[seg.color!] ?? Colors.white;
      }

      final style = widget.baseStyle.copyWith(
        color: color ?? widget.baseStyle.color,
        fontWeight: seg.bold ? FontWeight.bold : null,
        fontStyle: seg.italic ? FontStyle.italic : null,
        decoration: TextDecoration.combine([
          if (seg.underlined) TextDecoration.underline,
          if (seg.strikethrough) TextDecoration.lineThrough,
        ]),
      );

      final hasAction = seg.clickAction != null || seg.hoverAction != null;

      if (hasAction) {
        final key = '$i-${seg.text}';
        TapGestureRecognizer? recognizer;
        if (seg.clickAction != null) {
          recognizer = _tapGesturers.putIfAbsent(key, () {
            return TapGestureRecognizer()
              ..onTap = () => _handleClick(seg.clickAction!);
          });
        }

        String? tooltipText;
        if (seg.hoverAction != null && seg.hoverAction!.action == 'show_text') {
          tooltipText = seg.hoverAction!.text;
        }

        spans.add(
          TextSpan(
            text: seg.text,
            style: style.copyWith(
              decoration: TextDecoration.combine([
                if (seg.underlined) TextDecoration.underline,
                if (seg.strikethrough) TextDecoration.lineThrough,
                if (seg.clickAction != null && !seg.underlined)
                  TextDecoration.underline,
              ]),
              color: seg.clickAction != null ? (color ?? Colors.white) : color,
            ),
            recognizer: recognizer,
            mouseCursor: seg.clickAction != null
                ? SystemMouseCursors.click
                : null,
            onEnter: tooltipText != null ? (_) {} : null,
            attributes: tooltipText != null
                ? InlineSpanAttributes(
                    tooltip: TooltipSpan.message(tooltipText),
                  )
                : null,
          ),
        );
      } else {
        spans.add(TextSpan(text: seg.text, style: style));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans, style: widget.baseStyle),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final StreamProxy proxy;

  const ChatScreen({super.key, required this.proxy});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _chatSubscription;
  StreamSubscription<ChatDeniedEvent>? _chatDeniedSubscription;
  bool _sending = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _chatSubscription = widget.proxy.chatMessages.listen(_onChatMessage);
    _chatDeniedSubscription = widget.proxy.chatDeniedEvents.listen(
      _onChatDenied,
    );
    _loadCachedMessages();
  }

  Future<void> _loadCachedMessages() async {
    final cachedMessages = await widget.proxy.subscribeToChat();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.addAll(cachedMessages);
      _loading = false;
    });
    _scrollToBottom();
  }

  void _onChatMessage(ChatMessage message) {
    if (!mounted) return;
    setState(() {
      _messages.add(message);
      if (_messages.length > 100) {
        _messages.removeAt(0);
      }
    });
    _scrollToBottom();
  }

  void _onChatDenied(ChatDeniedEvent event) {
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message denied: ${event.reason}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _chatDeniedSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    widget.proxy.unsubscribeFromChat();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (text.startsWith('/')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commands must use the command palette'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _sending = true);

    final sent = widget.proxy.trySendChatMessage(text);
    if (sent) {
      _messageController.clear();
      setState(() {
        _messages.add(ChatMessage.outgoing(text));
        _sending = false;
      });
      _scrollToBottom();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg.isOutgoing;
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Colors.blue.withValues(alpha: 0.8)
                                : Colors.grey.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isMe)
                                Text(
                                  msg.sender,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              _RichText(
                                segments: msg.segments,
                                baseStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 8,
              right: 8,
              top: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          inputFormatters: [_SmartQuotesFormatter()],
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          onPressed: _sending ? null : _sendMessage,
                          icon: Icon(
                            Icons.send,
                            color: _sending ? Colors.white30 : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
