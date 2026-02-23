import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/services/chat_models.dart';
import 'package:monkeycraft_client/services/hibernation_models.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final void Function(String command)? onSuggestCommand;

  const _RichText({
    required this.segments,
    required this.baseStyle,
    this.proxy,
    this.onSuggestCommand,
  });

  @override
  State<_RichText> createState() => _RichTextState();
}

class _RichTextState extends State<_RichText> {
  OverlayEntry? _tooltipOverlay;

  Color? _parseColor(String? colorStr) {
    if (colorStr == null || !colorStr.startsWith('#') || colorStr.length != 7) {
      return null;
    }
    final value = int.tryParse(colorStr.substring(1), radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 + value);
  }

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _removeTooltip() {
    _tooltipOverlay?.remove();
    _tooltipOverlay = null;
  }

  void _showTooltip(List<ChatSegment> segments, Offset position) {
    _removeTooltip();

    final screenSize = MediaQuery.of(context).size;
    double left = position.dx;

    const tooltipHeight = 100.0;

    bool showAbove = position.dy + tooltipHeight > screenSize.height;

    double top = showAbove
        ? position.dy - tooltipHeight - 30
        : position.dy + 25;

    if (left + 200 > screenSize.width) {
      left = screenSize.width - 210;
    }
    if (left < 10) left = 10;
    if (top < 10) top = 10;

    final spans = <InlineSpan>[];
    for (final seg in segments) {
      final color = _parseColor(seg.color);
      spans.add(
        TextSpan(
          text: seg.text,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 13,
            fontWeight: seg.bold ? FontWeight.bold : null,
            fontStyle: seg.italic ? FontStyle.italic : null,
            decoration: TextDecoration.combine([
              if (seg.underlined) TextDecoration.underline,
              if (seg.strikethrough) TextDecoration.lineThrough,
            ]),
          ),
        ),
      );
    }

    final overlay = Overlay.of(context);
    _tooltipOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text.rich(TextSpan(children: spans)),
          ),
        ),
      ),
    );
    overlay.insert(_tooltipOverlay!);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _removeTooltip();
    });
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
        widget.proxy?.trySendRunCommand(action.value);
        break;
      case 'suggest_command':
        widget.onSuggestCommand?.call(action.value);
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

  TextStyle _getStyleForSegment(ChatSegment seg, Color? color) {
    return widget.baseStyle.copyWith(
      color: color ?? widget.baseStyle.color,
      fontWeight: seg.bold ? FontWeight.bold : null,
      fontStyle: seg.italic ? FontStyle.italic : null,
      decoration: TextDecoration.combine([
        if (seg.underlined) TextDecoration.underline,
        if (seg.strikethrough) TextDecoration.lineThrough,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();

    final spans = <InlineSpan>[];

    for (final seg in widget.segments) {
      final color = _parseColor(seg.color);

      final style = _getStyleForSegment(seg, color);
      final hasClick = seg.clickAction != null;
      final hasHover =
          seg.hoverAction != null &&
          seg.hoverAction!.action == 'show_text' &&
          seg.hoverAction!.segments.isNotEmpty;

      if (!hasClick && !hasHover) {
        spans.add(TextSpan(text: seg.text, style: style));
        continue;
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (hasClick) {
                _handleClick(seg.clickAction!);
              } else if (hasHover) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final pos = box.localToGlobal(Offset.zero);
                  _showTooltip(
                    seg.hoverAction!.segments,
                    Offset(pos.dx + 50, pos.dy),
                  );
                }
              }
            },
            onLongPress: () {
              if (hasHover) {
                final box = context.findRenderObject() as RenderBox?;
                if (box != null) {
                  final pos = box.localToGlobal(Offset.zero);
                  _showTooltip(
                    seg.hoverAction!.segments,
                    Offset(pos.dx + 50, pos.dy),
                  );
                }
              }
            },
            child: Text(
              seg.text,
              style: style.copyWith(
                height: 1.0,
                decoration: TextDecoration.combine([
                  if (seg.underlined) TextDecoration.underline,
                  if (seg.strikethrough) TextDecoration.lineThrough,
                  if (hasClick && !seg.underlined) TextDecoration.underline,
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return SelectableText.rich(
      TextSpan(children: spans, style: widget.baseStyle),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final StreamProxy proxy;
  final bool manageConnection;

  const ChatScreen({
    super.key,
    required this.proxy,
    this.manageConnection = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  StreamSubscription<ChatMessage>? _chatSubscription;
  StreamSubscription<ChatDeniedEvent>? _chatDeniedSubscription;
  StreamSubscription<HibernationEvent>? _hibernationSubscription;
  StreamSubscription<NudgeNotification>? _nudgeSubscription;
  StreamSubscription<TimedNotification>? _timedSubscription;
  StreamSubscription<ImmediateNotification>? _immediateSubscription;
  StreamSubscription<ServerDisconnectEvent>? _serverDisconnectSubscription;
  StreamSubscription<void>? _connectionLostSubscription;
  StreamSubscription<void>? _connectionRestoredSubscription;
  bool _loading = true;
  bool _reconnecting = false;
  String? _server;
  String? _password;
  bool _credentialsLoaded = false;
  int _reconnectAttempts = 0;
  bool _hibernating = false;
  String _hibernationMessage = '';
  bool _hibernationBannerDismissed = false;
  NudgeNotification? _currentNudge;
  ImmediateNotification? _currentImmediate;
  bool _nudgeBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[ChatScreen] initState');
    WidgetsBinding.instance.addObserver(this);
    _chatSubscription = widget.proxy.chatMessages.listen(_onChatMessage);
    _chatDeniedSubscription = widget.proxy.chatDeniedEvents.listen(
      _onChatDenied,
    );
    _hibernationSubscription = widget.proxy.hibernationEvents.listen(
      _onHibernationEvent,
    );
    _nudgeSubscription = widget.proxy.nudges.listen(_onNudge);
    _immediateSubscription = widget.proxy.immediateNotifications.listen(
      _onImmediateNotification,
    );
    _serverDisconnectSubscription = widget.proxy.serverDisconnectEvents.listen(
      _onServerDisconnect,
    );
    _connectionLostSubscription = widget.proxy.connectionLostEvents.listen(
      (_) => _onConnectionLost(),
    );
    _connectionRestoredSubscription = widget.proxy.connectionRestoredEvents
        .listen((_) => _onConnectionRestored());
    _loadReconnectCredentials();
    _loadCachedMessages();
  }

  Future<void> _loadReconnectCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _server = prefs.getString('server') ?? '127.0.0.1:9600';
    _password = prefs.getString('password') ?? '';
    _credentialsLoaded = true;
    debugPrint('[ChatScreen] Credentials loaded: server=$_server');
  }

  Future<void> _loadCachedMessages() async {
    final cachedMessages = await widget.proxy.subscribeToChat();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.addAll(cachedMessages);
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(immediate: true);
      });
    });
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Message denied: ${event.reason}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _onHibernationEvent(HibernationEvent event) {
    if (!mounted) return;
    if (event is HibernationStatus) {
      setState(() {
        if (event.active) {
          if (!_hibernating) {
            _hibernationBannerDismissed = false;
          }
          _hibernating = true;
          _hibernationMessage = event.message ?? _hibernationMessage;
        } else {
          _hibernating = false;
          _hibernationMessage = '';
          _hibernationBannerDismissed = false;
        }
      });
    }
  }

  void _onNudge(NudgeNotification nudge) {
    if (!mounted) return;
    setState(() {
      _currentNudge = nudge;
      _nudgeBannerDismissed = false;
    });
  }

  void _onImmediateNotification(ImmediateNotification notification) {
    if (!mounted) return;
    setState(() {
      _currentImmediate = notification;
    });
  }

  void _onServerDisconnect(ServerDisconnectEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disconnected by server'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _onConnectionLost() {
    debugPrint('[ChatScreen] Connection lost event received');
    if (!mounted) return;
    _reconnect();
  }

  void _onConnectionRestored() {
    debugPrint('[ChatScreen] Connection restored event received');
    if (!mounted) return;
    _reattachChatStreams();
    _loadCachedMessages();
  }

  void _scrollToBottom({bool immediate = false}) {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (immediate) {
          _scrollController.jumpTo(maxScroll);
        } else {
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatSubscription?.cancel();
    _chatDeniedSubscription?.cancel();
    _hibernationSubscription?.cancel();
    _nudgeSubscription?.cancel();
    _immediateSubscription?.cancel();
    _serverDisconnectSubscription?.cancel();
    _connectionLostSubscription?.cancel();
    _connectionRestoredSubscription?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    widget.proxy.unsubscribeFromChat();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
      '[ChatScreen] App lifecycle changed: $state, manageConnection=${widget.manageConnection}',
    );
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        '[ChatScreen] App resumed, isConnected=${widget.proxy.isConnected}, reconnecting=$_reconnecting',
      );
      if (widget.manageConnection) {
        // This screen owns the connection, reconnect it
        if (!_credentialsLoaded) {
          debugPrint('[ChatScreen] Credentials not loaded yet, waiting...');
          _loadReconnectCredentials().then((_) => _reconnect());
        } else {
          _reconnect();
        }
      } else {
        // Connection managed externally, just re-attach streams if connected
        if (widget.proxy.isConnected) {
          debugPrint('[ChatScreen] Already connected, re-attaching streams');
          _reattachChatStreams();
          _loadCachedMessages();
        } else {
          debugPrint(
            '[ChatScreen] Not connected, waiting for external reconnection',
          );
        }
      }
    }
  }

  Future<void> _reconnect() async {
    debugPrint(
      '[ChatScreen] _reconnect() called, reconnecting=$_reconnecting, mounted=$mounted',
    );
    if (_reconnecting || !mounted) return;
    final server = _server;
    final password = _password;
    if (server == null || password == null) {
      debugPrint(
        '[ChatScreen] Cannot reconnect: server=$server, password=${password != null ? "set" : "null"}',
      );
      return;
    }

    _reconnecting = true;
    _reconnectAttempts++;
    debugPrint(
      '[ChatScreen] Starting reconnection attempt #$_reconnectAttempts to $server',
    );
    try {
      await widget.proxy.start(server, password);
      debugPrint(
        '[ChatScreen] proxy.start() completed, isConnected=${widget.proxy.isConnected}',
      );
      widget.proxy.sendPing();
    } catch (e, st) {
      debugPrint('[ChatScreen] Reconnection failed: $e');
      debugPrint('[ChatScreen] Stack trace: $st');
    } finally {
      _reconnecting = false;
    }

    if (mounted && widget.proxy.isConnected) {
      debugPrint('[ChatScreen] Reconnection successful, reattaching streams');
      _reattachChatStreams();
      await _loadCachedMessages();
      _reconnectAttempts = 0;
    } else {
      debugPrint(
        '[ChatScreen] Reconnection not successful, mounted=$mounted, isConnected=${widget.proxy.isConnected}',
      );
    }
  }

  void _reattachChatStreams() {
    debugPrint('[ChatScreen] Reattaching all chat streams');
    _chatSubscription?.cancel();
    _chatDeniedSubscription?.cancel();
    _hibernationSubscription?.cancel();
    _nudgeSubscription?.cancel();
    _timedSubscription?.cancel();
    _serverDisconnectSubscription?.cancel();
    _connectionLostSubscription?.cancel();
    _connectionRestoredSubscription?.cancel();
    _chatSubscription = widget.proxy.chatMessages.listen(_onChatMessage);
    _chatDeniedSubscription = widget.proxy.chatDeniedEvents.listen(
      _onChatDenied,
    );
    _hibernationSubscription = widget.proxy.hibernationEvents.listen(
      _onHibernationEvent,
    );
    _nudgeSubscription = widget.proxy.nudges.listen(_onNudge);
    _immediateSubscription = widget.proxy.immediateNotifications.listen(
      _onImmediateNotification,
    );
    _serverDisconnectSubscription = widget.proxy.serverDisconnectEvents.listen(
      _onServerDisconnect,
    );
    _connectionLostSubscription = widget.proxy.connectionLostEvents.listen(
      (_) => _onConnectionLost(),
    );
    _connectionRestoredSubscription = widget.proxy.connectionRestoredEvents
        .listen((_) => _onConnectionRestored());
    debugPrint('[ChatScreen] All streams reattached');
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final sent = text.startsWith('/')
        ? widget.proxy.trySendRunCommand(text)
        : widget.proxy.trySendChatMessage(text);

    if (sent) {
      _messageController.clear();
    }
  }

  void _dismissHibernationBanner() {
    setState(() {
      _hibernationBannerDismissed = true;
    });
  }

  void _dismissNudgeBanner() {
    setState(() {
      _nudgeBannerDismissed = true;
    });
  }

  void _onSuggestCommand(String command) {
    _messageController.text = command;
    _messageController.selection = TextSelection.collapsed(
      offset: command.length,
    );
    _messageFocusNode.requestFocus();
  }

  Widget _buildDynamicIsland() {
    String? bannerText;
    Color backgroundColor;
    Color textColor;
    VoidCallback onDismiss;

    if (_hibernating &&
        !_hibernationBannerDismissed &&
        _hibernationMessage.isNotEmpty) {
      bannerText = _hibernationMessage;
      backgroundColor = const Color(0xFF2E7D32);
      textColor = Colors.white;
      onDismiss = _dismissHibernationBanner;
    } else if (_currentImmediate != null) {
      bannerText = _currentImmediate!.body ?? '';
      if (bannerText.isEmpty) return const SizedBox.shrink();
      backgroundColor = const Color(0xFF666666);
      textColor = Colors.white;
      onDismiss = () {
        setState(() {
          _currentImmediate = null;
        });
      };
    } else if (!_hibernating &&
        _currentNudge != null &&
        !_nudgeBannerDismissed) {
      final title = _currentNudge!.title ?? '';
      final body = _currentNudge!.body ?? '';
      bannerText = body.isNotEmpty
          ? (title.isNotEmpty ? '$title: $body' : body)
          : title;
      if (bannerText.isEmpty) return const SizedBox.shrink();
      backgroundColor = const Color(0xFF1A1A1A);
      textColor = Colors.white70;
      onDismiss = _dismissNudgeBanner;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              bannerText,
              style: TextStyle(color: textColor, fontSize: 12, height: 1.3),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                size: 16,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
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
          _buildDynamicIsland(),
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
                      horizontal: 8,
                      vertical: 8,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: _RichText(
                          segments: msg.segments,
                          baseStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          proxy: widget.proxy,
                          onSuggestCommand: _onSuggestCommand,
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
                          focusNode: _messageFocusNode,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          keyboardType: TextInputType.text,
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
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send, color: Colors.white),
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
