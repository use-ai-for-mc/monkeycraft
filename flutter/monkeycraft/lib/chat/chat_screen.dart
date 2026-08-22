import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/chat/chat_models.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/chat/chat_rich_text.dart';

class ChatScreen extends StatefulWidget {
  final StreamProxy proxy;
  final SessionController? session;
  final bool manageConnection;

  const ChatScreen({
    super.key,
    required this.proxy,
    this.session,
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
  StreamSubscription<SessionState>? _sessionStateSubscription;
  StreamSubscription<NudgeNotification>? _nudgeSubscription;
  StreamSubscription<ImmediateNotification>? _immediateSubscription;
  StreamSubscription<ServerDisconnectEvent>? _serverDisconnectSubscription;
  StreamSubscription<void>? _connectionLostSubscription;
  StreamSubscription<void>? _connectionRestoredSubscription;
  bool _loading = true;
  bool _showScrollToBottom = false;
  bool _closing = false;

  AppLifecycleState? _lastLifecycleState;
  bool _isProcessingLifecycle = false;

  VideoState _videoState = VideoState.active;
  String _videoStateMessage = '';
  bool _hibernationBannerDismissed = false;
  NudgeNotification? _currentNudge;
  ImmediateNotification? _currentImmediate;
  bool _nudgeBannerDismissed = false;

  StreamSubscription<List<String>>? _playerListSubscription;
  StreamSubscription<int>? _playerCountSubscription;
  List<String> _onlinePlayers = [];
  int _onlineCount = 0;
  bool _playerListSupported = false;
  Timer? _playerCountTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _chatSubscription = widget.proxy.chatMessages.listen(_onChatMessage);
    _chatDeniedSubscription = widget.proxy.chatDeniedEvents.listen(
      _onChatDenied,
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

    _playerCountSubscription = widget.proxy.playerCountEvents.listen(
      _onPlayerCountUpdate,
    );
    _playerListSubscription = widget.proxy.playerListEvents.listen(
      _onPlayerListUpdate,
    );
    _playerListSupported = widget.proxy.serverSupports('PLAYER_LIST');
    _onlineCount = widget.proxy.playerCount;
    _onlinePlayers = widget.proxy.playerList;
    _refreshPlayerCount();
    _playerCountTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshPlayerCount(),
    );

    if (widget.session != null) {
      _sessionStateSubscription = widget.session!.stateStream.listen(
        _onSessionStateChanged,
      );
      _videoState = widget.session!.state.videoState;
      _videoStateMessage = widget.session!.state.videoStateMessage;
    }

    openAudioMcService.setInfoPacketHandler((packet) {
      widget.proxy.trySendCommand(packet);
    });

    openAudioMcService.setOnFailureHandler(() {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OpenAudioMC fails to open'),
              Text('The link may have already expired.'),
            ],
          ),
          duration: Duration(seconds: 4),
        ),
      );
    });

    mcParksV1Service.setInfoPacketHandler((packet) {
      widget.proxy.trySendCommand(packet);
    });

    mcParksV1Service.setOnFailureHandler(() {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('MCParks audio session failed to open'),
          duration: Duration(seconds: 4),
        ),
      );
    });

    _loadCachedMessages();
  }

  void _onSessionStateChanged(SessionState state) {
    if (!mounted) return;

    if (state.shouldReturnToLogin && !_closing) {
      _closeScreenAndReturnToLogin();
      return;
    }

    setState(() {
      if (state.videoState == VideoState.hibernating) {
        _videoState = state.videoState;
        _videoStateMessage = state.videoStateMessage;
        _hibernationBannerDismissed = false;
      } else if (state.videoState == VideoState.active) {
        _videoState = state.videoState;
        _videoStateMessage = '';
        _hibernationBannerDismissed = false;
      }
    });
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

  void _onPlayerCountUpdate(int count) {
    if (!mounted) return;
    setState(() {
      _onlineCount = count;
    });
  }

  void _onPlayerListUpdate(List<String> players) {
    if (!mounted) return;
    setState(() {
      _onlinePlayers = players;
      _onlineCount = players.length;
    });
  }

  void _refreshPlayerCount() {
    if (!mounted || !_playerListSupported) return;
    widget.proxy.requestPlayerCount();
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
    if (_closing) return;
    widget.session?.handleConnectionLost();
  }

  Future<void> _closeScreenAndReturnToLogin() async {
    if (_closing) return;
    _closing = true;

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _onConnectionRestored() {
    if (!mounted) return;
    widget.session?.resetReconnectionState();
    setState(() {
      _playerListSupported = widget.proxy.serverSupports('PLAYER_LIST');
    });
    _reattachChatStreams();
    _loadCachedMessages();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      final shouldShow = maxScroll - currentScroll > 100;
      if (shouldShow != _showScrollToBottom) {
        setState(() => _showScrollToBottom = shouldShow);
      }
    }
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
    _sessionStateSubscription?.cancel();
    _nudgeSubscription?.cancel();
    _immediateSubscription?.cancel();
    _serverDisconnectSubscription?.cancel();
    _connectionLostSubscription?.cancel();
    _connectionRestoredSubscription?.cancel();
    _playerListSubscription?.cancel();
    _playerCountSubscription?.cancel();
    _playerCountTimer?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    widget.proxy.unsubscribeFromChat();
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    _lastLifecycleState = state;

    if (_isProcessingLifecycle) {
      return;
    }

    _isProcessingLifecycle = true;
    while (_lastLifecycleState != null) {
      final currentState = _lastLifecycleState!;
      _lastLifecycleState = null;
      try {
        if (currentState == AppLifecycleState.resumed) {
          openAudioMcService.softRefresh();
          mcParksV1Service.softRefresh();
          if (widget.manageConnection) {
            await _reconnect();
          } else {
            if (widget.proxy.isConnected) {
              _reattachChatStreams();
              await _loadCachedMessages();
            }
          }
        }
      } catch (e) {
        debugPrint('ChatScreen lifecycle error: $e');
      }
    }
    _isProcessingLifecycle = false;
  }

  Future<void> _reconnect() async {
    if (!mounted || _closing) return;

    final session = widget.session;
    if (session == null) return;

    if (widget.proxy.isConnected) {
      session.resetReconnectionState();
      _reattachChatStreams();
      await _loadCachedMessages();
      return;
    }

    try {
      await session.resumeConnection();
    } catch (e) {
      debugPrint('ChatScreen: failed to resume connection: $e');
    }
  }

  void _reattachChatStreams() {
    _chatSubscription?.cancel();
    _chatDeniedSubscription?.cancel();
    _nudgeSubscription?.cancel();
    _serverDisconnectSubscription?.cancel();
    _connectionLostSubscription?.cancel();
    _connectionRestoredSubscription?.cancel();
    _chatSubscription = widget.proxy.chatMessages.listen(_onChatMessage);
    _chatDeniedSubscription = widget.proxy.chatDeniedEvents.listen(
      _onChatDenied,
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
    _playerListSubscription?.cancel();
    _playerListSubscription = widget.proxy.playerListEvents.listen(
      _onPlayerListUpdate,
    );
    _playerCountSubscription?.cancel();
    _playerCountSubscription = widget.proxy.playerCountEvents.listen(
      _onPlayerCountUpdate,
    );
    _refreshPlayerCount();
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

  Widget _buildOnlineIndicator() {
    if (!_playerListSupported) return const SizedBox.shrink();
    final count = _onlineCount;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _showPlayerListSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people, size: 18, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlayerListSheet() {
    widget.proxy.requestPlayerList();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: StreamBuilder<List<String>>(
            stream: widget.proxy.playerListEvents,
            initialData: _onlinePlayers,
            builder: (context, snapshot) {
              final players = snapshot.data ?? const <String>[];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.people, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          players.isEmpty
                              ? 'No players online'
                              : '${players.length} player${players.length == 1 ? '' : 's'} online',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: players.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 18,
                        ),
                        title: Text(
                          players[i],
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDynamicIsland() {
    String? bannerText;
    Color backgroundColor;
    Color textColor;
    VoidCallback onDismiss;

    if (_videoState == VideoState.hibernating &&
        !_hibernationBannerDismissed &&
        _videoStateMessage.isNotEmpty) {
      bannerText = _videoStateMessage;
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
    } else if (_videoState == VideoState.active &&
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
        actions: [_buildOnlineIndicator()],
      ),
      body: ListenableBuilder(
        listenable: appSettings,
        builder: (context, _) {
          final bgPath = appSettings.chatBackgroundPath;
          return Stack(
            children: [
              if (bgPath != null)
                Positioned.fill(
                  child: Image.file(
                    File(bgPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              if (bgPath != null)
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.65)),
                ),
              SafeArea(
                top: true,
                bottom: false,
                child: Column(
                  children: [
                    _buildDynamicIsland(),
                    Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _messages.isEmpty
                          ? const Center(
                              child: Text(
                                'No messages yet',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 16,
                                ),
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: ChatRichText(
                                    segments: msg.segments,
                                    baseStyle: appSettings.textStyleWithFont(
                                      const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    proxy: widget.proxy,
                                    openAudioMc: openAudioMcService,
                                    mcParksV1: mcParksV1Service,
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
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                      ),
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
                                style: appSettings.textStyleWithFont(
                                  const TextStyle(color: Colors.white),
                                ),
                                textInputAction: TextInputAction.send,
                                keyboardType: TextInputType.text,
                                inputFormatters: [],
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  hintStyle: appSettings.textStyleWithFont(
                                    const TextStyle(color: Colors.white54),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
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
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _showScrollToBottom
          ? FloatingActionButton(
              mini: true,
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              onPressed: () => _scrollToBottom(),
              child: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            )
          : null,
    );
  }
}
