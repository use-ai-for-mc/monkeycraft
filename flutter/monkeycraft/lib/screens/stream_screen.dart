import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/services/game_input_controller.dart';
import 'package:monkeycraft_client/services/ios_timed_notification_scheduler.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/protocol_models.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';
import 'package:monkeycraft_client/services/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/services/live_activity_service.dart';
import 'package:monkeycraft_client/services/stream_resolution.dart';
import 'package:monkeycraft_client/services/stream_settings.dart';
import 'package:monkeycraft_client/services/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/services/timed_notification_service.dart';
import 'package:monkeycraft_client/services/session_controller.dart';
import 'package:monkeycraft_client/screens/stream_settings_screen.dart';
import 'package:monkeycraft_client/screens/chat_screen.dart';
import 'package:monkeycraft_client/widgets/hotbar_selector.dart';
import 'package:monkeycraft_client/widgets/jump_button.dart';
import 'package:monkeycraft_client/widgets/look_pad.dart';
import 'package:monkeycraft_client/widgets/shift_button.dart';
import 'package:monkeycraft_client/widgets/virtual_joystick.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StreamScreen extends StatefulWidget {
  final StreamProxy proxy;

  const StreamScreen({super.key, required this.proxy});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen>
    with WidgetsBindingObserver {
  late final GameInputController _input;
  late final TimedNotificationCoordinator _timedCoordinator;
  late final IosTimedNotificationScheduler _timedScheduler;
  late final StreamSettingsStore _settingsStore;
  late final SessionController _session;

  final _liveActivityService = LiveActivityService();
  bool _hotbarExpanded = false;
  int _selectedHotbarSlot = 0;
  StreamSettings _settings = StreamSettings.defaults;

  StreamSubscription<NudgeNotification>? _nudgeSub;
  StreamSubscription<DateTime>? _heartbeatAckSub;
  StreamSubscription<CommandDeniedEvent>? _commandDeniedSub;
  StreamSubscription<ServerDisconnectEvent>? _serverDisconnectSub;
  StreamSubscription<Uint8List>? _accessUnitSub;
  StreamSubscription<SessionState>? _sessionStateSub;
  StreamSubscription<void>? _connectionLostSub;

  Timer? _notificationCheckTimer;
  Timer? _reconnectRetryTimer;
  int _reconnectRetryCount = 0;
  static const int _maxReconnectRetries = 3;
  bool? _lastIsPortrait;
  Size? _lastScreenSize;
  bool _closing = false;
  bool _reconnecting = false;
  String? _server;
  String? _password;
  bool? _forcedOrientation;

  ClientMode? _lastHandledMode;
  VideoState? _lastHandledVideoState;
  int? _lastFiredTimedNotificationMs;

  bool get _supportedPlatform => Platform.isIOS || Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input = GameInputController(
      (key, pressed) => widget.proxy.sendCommand({
        'type': 'INPUT',
        'key': key,
        'pressed': pressed,
      }),
    );
    _timedScheduler = IosTimedNotificationScheduler(TimedNotificationService());
    _timedCoordinator = TimedNotificationCoordinator(
      scheduler: _timedScheduler,
    );
    _settingsStore = StreamSettingsStore();
    _session = SessionController(
      proxy: widget.proxy,
      settingsStore: _settingsStore,
    );
    _loadStreamSettings();
    _liveActivityService.init();
    _session.initialize();
    _attachProxyStreams();
    _attachSessionState();
    _loadReconnectCredentials();

    _notificationCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkTimedNotification();
      _session.checkWaitingForStream();
      _checkVideoStateStaleness();
    });

    if (_supportedPlatform) {
      _initHardwareDecoder().then((_) {
        if (mounted) _syncClientStatus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncClientStatus();
      });
    }
  }

  void _attachProxyStreams() {
    debugPrint('[StreamScreen] _attachProxyStreams');
    _nudgeSub?.cancel();
    _nudgeSub = widget.proxy.nudges.listen(_handleNudge);
    _commandDeniedSub?.cancel();
    _commandDeniedSub = widget.proxy.commandDeniedEvents.listen(
      _handleCommandDenied,
    );
    _serverDisconnectSub?.cancel();
    _serverDisconnectSub = widget.proxy.serverDisconnectEvents.listen(
      _handleServerDisconnect,
    );
    _heartbeatAckSub?.cancel();
    _heartbeatAckSub = widget.proxy.heartbeatAcks.listen((time) {
      _session.updateHeartbeatAckTime();
      _reconnectRetryCount = 0;
    });
    _connectionLostSub?.cancel();
    _connectionLostSub = widget.proxy.connectionLostEvents.listen((_) {
      debugPrint('[StreamScreen] Connection lost event received');
      _handleConnectionLost();
    });
  }

  void _attachSessionState() {
    _sessionStateSub?.cancel();
    _sessionStateSub = _session.stateStream.listen((state) {
      debugPrint('[StreamScreen] Session state changed: $state');
      if (mounted) setState(() {});

      // Handle state transitions
      final modeChanged = _lastHandledMode != state.mode;
      final videoStateChanged = _lastHandledVideoState != state.videoState;

      if (modeChanged || videoStateChanged) {
        _handleStateTransition(
          fromMode: _lastHandledMode,
          toMode: state.mode,
          fromVideoState: _lastHandledVideoState,
          toVideoState: state.videoState,
          message: state.videoStateMessage,
        );
      }

      // Handle timed notification
      if (state.hasTimedNotification) {
        _handleTimedNotification(state.timedNotification!);
      }

      _lastHandledMode = state.mode;
      _lastHandledVideoState = state.videoState;
    });
  }

  Future<void> _handleStateTransition({
    ClientMode? fromMode,
    required ClientMode toMode,
    VideoState? fromVideoState,
    required VideoState toVideoState,
    required String message,
  }) async {
    debugPrint(
      '[StreamScreen] State transition: mode $fromMode -> $toMode, videoState $fromVideoState -> $toVideoState',
    );

    // Entering hibernation while streaming
    if (toVideoState == VideoState.hibernating &&
        fromVideoState != VideoState.hibernating &&
        toMode == ClientMode.streaming) {
      _handleEnterHibernation(message);
    }

    // Exiting hibernation while streaming
    if (toVideoState == VideoState.active &&
        fromVideoState == VideoState.hibernating &&
        toMode == ClientMode.streaming) {
      _handleExitHibernation();
    }
  }

  Future<void> _handleEnterHibernation(String message) async {
    debugPrint('[StreamScreen] _handleEnterHibernation: "$message"');
    _input.releaseAll();
    await _pauseVideoPipeline();

    if (_session.shouldAutoNavigateToChat && mounted) {
      debugPrint('[StreamScreen] Auto-navigating to chat');
      await _openChatScreenAuto();
    }
  }

  Future<void> _handleExitHibernation() async {
    debugPrint('[StreamScreen] _handleExitHibernation');
    if (!mounted) return;
    await _restartStream();
    _session.refreshVideo();
  }

  void _handleConnectionLost() {
    debugPrint('[StreamScreen] _handleConnectionLost');
    if (_closing || _reconnecting) return;
    _scheduleReconnectRetry();
  }

  void _scheduleReconnectRetry() {
    _reconnectRetryTimer?.cancel();
    if (_reconnectRetryCount >= _maxReconnectRetries) {
      debugPrint(
        '[StreamScreen] Max reconnect retries reached, returning to login',
      );
      _closeScreenAndReturnToLogin();
      return;
    }
    final delay = Duration(seconds: 1 << _reconnectRetryCount);
    debugPrint(
      '[StreamScreen] Scheduling reconnect retry ${_reconnectRetryCount + 1}/$_maxReconnectRetries in ${delay.inSeconds}s',
    );
    _reconnectRetryTimer = Timer(delay, () {
      if (!_closing && !_reconnecting && mounted) {
        _resumeIfNeededWithRetry();
      }
    });
  }

  Future<void> _closeScreenAndReturnToLogin() async {
    if (_closing) return;
    _closing = true;

    _input.releaseAll();
    SystemChrome.setPreferredOrientations([]);

    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;
    await _connectionLostSub?.cancel();
    _connectionLostSub = null;
    _reconnectRetryTimer?.cancel();

    await _session.disposeDecoder();
    _session.dispose();
    _liveActivityService.dispose();
    await widget.proxy.stop();

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _resumeIfNeededWithRetry() async {
    await _resumeIfNeeded();
    if (!widget.proxy.isConnected &&
        _reconnectRetryCount < _maxReconnectRetries) {
      _reconnectRetryCount++;
      _scheduleReconnectRetry();
    }
  }

  void _handleTimedNotification(TimedNotification notification) {
    _timedCoordinator.handle(notification);
    if (notification.fireAtEpochMs != null) {
      _liveActivityService.startCountdown(
        fireAtEpochMs: notification.fireAtEpochMs!,
        title: notification.title ?? 'MonkeyCraft',
        body: notification.body ?? '',
        countDownText: notification.countDownText ?? 'TBA',
      );
    } else {
      _liveActivityService.cancel();
    }
  }

  void _checkTimedNotification() {
    if (!_session.state.foreground) return;
    final notification = _session.state.timedNotification;
    if (notification == null || notification.fireAtEpochMs == null) return;
    final fireAtMs = notification.fireAtEpochMs!;

    // Skip if we already fired this notification
    if (_lastFiredTimedNotificationMs == fireAtMs) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (fireAtMs <= now) {
      _lastFiredTimedNotificationMs = fireAtMs;
      _showNotificationNow(notification);
      widget.proxy.sendPing();
      _liveActivityService.cancel();
    }
  }

  void _checkVideoStateStaleness() {
    final state = _session.state;
    if (state.videoState != VideoState.hibernating ||
        !state.foreground ||
        !widget.proxy.isConnected) {
      return;
    }
    final age = widget.proxy.timeSinceLastVideoStateEvent;
    if (age != null && age.inSeconds >= 5) {
      debugPrint(
        '[StreamScreen] Video state stale (${age.inSeconds}s), sending PING',
      );
      widget.proxy.sendPing();
    }
  }

  void _showNotificationNow(TimedNotification notification) {
    final title = notification.title ?? 'MonkeyCraft';
    final body = notification.body ?? '';
    final text = body.isEmpty ? title : '$title\n$body';
    if (notification.sound) {
      _timedScheduler.playNotificationSound();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleCommandDenied(CommandDeniedEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Command not allowed: ${event.command}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleServerDisconnect(ServerDisconnectEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disconnected by server'),
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _pauseVideoPipeline() async {
    debugPrint('[StreamScreen] _pauseVideoPipeline: cancelling accessUnitSub');
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _session.disposeDecoder();
    debugPrint('[StreamScreen] _pauseVideoPipeline: complete');
  }

  void _syncClientStatus() {
    final resolution = _currentTargetResolution();
    _session.syncStatus(resolution: resolution);
  }

  Future<void> _openChatScreenAuto() async {
    debugPrint('[StreamScreen] _openChatScreenAuto');
    _session.setMode(ClientMode.chat);
    _input.releaseAll();
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;

    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChatScreen(proxy: widget.proxy, session: _session),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (animation.status == AnimationStatus.reverse) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          }
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );
    debugPrint('[StreamScreen] Chat screen closed (auto)');

    if (!mounted) return;
    // Switch back to streaming mode
    _session.setMode(
      ClientMode.streaming,
      resolution: _currentTargetResolution(),
    );

    if (_session.state.videoState == VideoState.active) {
      debugPrint('[StreamScreen] Returning to streaming mode');
      await _restartStream();
    }
  }

  Future<void> _openChatScreen() async {
    debugPrint('[StreamScreen] _openChatScreen: entering chat mode');
    _session.setMode(ClientMode.chat);
    _input.releaseAll();
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;

    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChatScreen(proxy: widget.proxy, session: _session),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          if (animation.status == AnimationStatus.reverse) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          }
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );

    debugPrint(
      '[StreamScreen] _openChatScreen: chat closed, returning to streaming',
    );
    if (!mounted) return;
    _session.setMode(
      ClientMode.streaming,
      resolution: _currentTargetResolution(),
    );
    await _restartStream();
  }

  Future<void> _loadReconnectCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _server = prefs.getString('server') ?? '127.0.0.1:9600';
    _password = prefs.getString('password') ?? '';
  }

  Future<void> _loadStreamSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _session.updateSettings(settings);
    });
  }

  void _handleNudge(NudgeNotification nudge) {
    if (!_session.state.foreground) return;
    final title = nudge.title ?? 'MonkeyCraft';
    final body = nudge.body ?? '';
    _timedScheduler.showImmediate(title, body, nudge.sound);
    if (nudge.sound) {
      _timedScheduler.playNotificationSound();
    }
    if (!mounted || _session.state.isInChat) return;
    final text = body.isEmpty ? title : '$title\n$body';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _initHardwareDecoder() async {
    debugPrint('[StreamScreen] _initHardwareDecoder: fps=${_settings.fps}');
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;

    final decoder = HardwareH264Decoder();
    final textureId = await decoder.createDecoder(fps: _settings.fps);
    _session.decoder = decoder;
    _session.textureId = textureId;

    debugPrint(
      '[StreamScreen] _initHardwareDecoder: creating accessUnit subscription',
    );
    _accessUnitSub = widget.proxy.accessUnits.listen((data) {
      _session.decoder?.pushAccessUnit(data);
      _session.updateFrameTime();
    });
    debugPrint('[StreamScreen] Decoder ready, textureId=$textureId');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.releaseAll();
    _accessUnitSub?.cancel();
    _nudgeSub?.cancel();
    _heartbeatAckSub?.cancel();
    _commandDeniedSub?.cancel();
    _serverDisconnectSub?.cancel();
    _sessionStateSub?.cancel();
    _connectionLostSub?.cancel();
    _notificationCheckTimer?.cancel();
    _reconnectRetryTimer?.cancel();
    _session.disposeDecoder();
    _session.dispose();
    _liveActivityService.dispose();
    widget.proxy.stop();
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[StreamScreen] App lifecycle: $state');
    if (state == AppLifecycleState.resumed) {
      debugPrint('[StreamScreen] App resumed');
      _session.setForeground(true);
      _resumeIfNeeded();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      debugPrint('[StreamScreen] App inactive/paused');
      _session.setForeground(false);
      _pauseStreaming();
    }
  }

  Future<void> _pauseStreaming() async {
    debugPrint('[StreamScreen] _pauseStreaming, closing=$_closing');
    if (_closing) return;
    _input.releaseAll();
    _reconnectRetryTimer?.cancel();
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;
    await _heartbeatAckSub?.cancel();
    _heartbeatAckSub = null;
    await _session.disposeDecoder();
    await widget.proxy.stop();
  }

  Future<void> _resumeIfNeeded() async {
    debugPrint(
      '[StreamScreen] _resumeIfNeeded, closing=$_closing, reconnecting=$_reconnecting',
    );
    if (_closing || _reconnecting) return;
    if (!mounted) return;
    final server = _server;
    final password = _password;
    if (server == null || password == null) return;

    _reconnecting = true;
    debugPrint('[StreamScreen] Reconnecting to $server');
    try {
      await widget.proxy.start(server, password);
      debugPrint(
        '[StreamScreen] Connected, isConnected=${widget.proxy.isConnected}',
      );
      _session.updateConnectionState(widget.proxy.isConnected);
      _session.reattachToProxy();
      widget.proxy.sendPing();
      _attachProxyStreams();
      if (_supportedPlatform) {
        await _initHardwareDecoder();
      }
      _lastIsPortrait = null;
      _session.resetFrameTime();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Sync our current mode to the server
      _syncClientStatus();

      _reconnectRetryCount = 0;
      _reconnectRetryTimer?.cancel();
      debugPrint('[StreamScreen] Reconnection complete');
    } catch (e, st) {
      debugPrint('[StreamScreen] Reconnection failed: $e\n$st');
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _closeScreen() async {
    if (_closing) return;
    _closing = true;

    _input.releaseAll();
    SystemChrome.setPreferredOrientations([]);

    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;

    await _session.disposeDecoder();
    await widget.proxy.stop();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  StreamResolution _currentTargetResolution() {
    final mq = MediaQuery.of(context);
    return computeTargetResolution(
      logicalSize: mq.size,
      padding: mq.padding,
      devicePixelRatio: mq.devicePixelRatio,
      scale: _settings.resolutionScale,
      maxDim: _settings.maxDim,
    );
  }

  Widget _buildTextureWithAspectRatio(EdgeInsets pad) {
    final sw = _session.streamWidth;
    final sh = _session.streamHeight;
    if (sw <= 0 || sh <= 0) {
      return Padding(
        padding: pad,
        child: SizedBox.expand(child: Texture(textureId: _session.textureId!)),
      );
    }
    final mq = MediaQuery.of(context);
    final availableWidth = mq.size.width - pad.left - pad.right;
    final availableHeight = mq.size.height - pad.top - pad.bottom;
    final streamAspect = sw / sh;
    final availableAspect = availableWidth / availableHeight;
    double displayWidth, displayHeight;
    if (availableAspect > streamAspect) {
      displayHeight = availableHeight;
      displayWidth = displayHeight * streamAspect;
    } else {
      displayWidth = availableWidth;
      displayHeight = displayWidth / streamAspect;
    }
    return Padding(
      padding: pad,
      child: Center(
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: Texture(textureId: _session.textureId!),
        ),
      ),
    );
  }

  Future<void> _restartStream() async {
    final target = _currentTargetResolution();
    if (!_session.state.shouldStreamVideo) {
      debugPrint(
        '[StreamScreen] _restartStream: cannot restart (mode=${_session.state.mode}, videoState=${_session.state.videoState})',
      );
      return;
    }
    await _session.restartStream(target, onDecoderNeeded: _initHardwareDecoder);

    // Ensure subscription is set up even if decoder was reused
    if (_session.decoder != null && _accessUnitSub == null) {
      debugPrint(
        '[StreamScreen] _restartStream: recreating accessUnit subscription',
      );
      _accessUnitSub = widget.proxy.accessUnits.listen((data) {
        _session.decoder?.pushAccessUnit(data);
        _session.updateFrameTime();
      });
    }
  }

  Future<void> _openSettings() async {
    final next = await Navigator.of(context).push<StreamSettings>(
      MaterialPageRoute(
        builder: (context) => StreamSettingsScreen(initial: _settings),
      ),
    );
    if (next == null || next == _settings) return;
    await _settingsStore.save(next);
    if (!mounted) return;
    setState(() {
      _settings = next;
      _session.updateSettings(next);
    });
    await _pauseStreaming();
    if (mounted) {
      await _resumeIfNeeded();
    }
  }

  void _toggleOrientation() {
    setState(() {
      _forcedOrientation = _forcedOrientation == null
          ? true
          : (_forcedOrientation == true ? false : null);
      if (_forcedOrientation == true) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else if (_forcedOrientation == false) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([]);
      }
    });
  }

  Future<void> _openCommandPalette() async {
    if (!mounted) return;
    final controller = TextEditingController(text: '/');

    Future<void> submit(BuildContext ctx) async {
      final text = controller.text.trim();
      if (!text.startsWith('/')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Command must start with /')),
        );
        return;
      }
      final sent = widget.proxy.trySendRunCommand(text);
      if (!sent) {
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not connected')));
        return;
      }
      if (!ctx.mounted) return;
      Navigator.of(ctx).pop();
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return GestureDetector(
          onTap: () => FocusScope.of(ctx).unfocus(),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Material(
                  color: const Color(0xCC111111),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Command',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            textInputAction: TextInputAction.send,
                            style: const TextStyle(color: Colors.white),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[ -~]'),
                              ),
                            ],
                            decoration: InputDecoration(
                              hintText: '/warp home',
                              hintStyle: const TextStyle(color: Colors.white38),
                              helperText: 'Must start with /',
                              helperStyle: const TextStyle(
                                color: Colors.white54,
                              ),
                              filled: true,
                              fillColor: const Color(0x33111111),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => submit(ctx),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('Cancel'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => submit(ctx),
                                  child: const Text('Send'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportedPlatform) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unsupported platform',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This client supports iOS and Android only.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final state = _session.state;

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final mq = MediaQuery.of(context);
        final screenSize = mq.size;
        final pad = mq.padding;
        final safeW = (screenSize.width - pad.left - pad.right).clamp(
          0.0,
          double.infinity,
        );
        final safeH = (screenSize.height - pad.top - pad.bottom).clamp(
          0.0,
          double.infinity,
        );
        final shortSide = safeW < safeH ? safeW : safeH;
        final joystickSize = isPortrait
            ? shortSide.clamp(140.0, 190.0)
            : (shortSide * 0.65).clamp(110.0, 150.0);
        final jumpSize = isPortrait
            ? (shortSide * 0.42).clamp(74.0, 104.0)
            : (shortSide * 0.42).clamp(62.0, 86.0);
        final shiftSize = jumpSize;
        const buttonGap = 12.0;
        const hotbarToggleSize = 48.0;
        const hotbarGap = 8.0;
        final hotbarButtonSize = isPortrait
            ? 44.0
            : (((safeW - (20 * 2) - 16) - (hotbarGap * 8)) / 9.0).clamp(
                28.0,
                40.0,
              );

        final joystickRect = Rect.fromLTWH(
          pad.left + 16,
          screenSize.height - (pad.bottom + 16 + joystickSize),
          joystickSize,
          joystickSize,
        );
        final jumpRect = Rect.fromLTWH(
          screenSize.width - (pad.right + 16 + jumpSize),
          screenSize.height -
              (pad.bottom + 16 + shiftSize + buttonGap + jumpSize),
          jumpSize,
          jumpSize,
        );
        final shiftRect = Rect.fromLTWH(
          screenSize.width - (pad.right + 16 + shiftSize),
          screenSize.height - (pad.bottom + 16 + shiftSize),
          shiftSize,
          shiftSize,
        );
        final topBarY = pad.top + 12;
        final closeRectSafe = Rect.fromLTWH(
          screenSize.width - (pad.right + 20 + 48),
          topBarY,
          48,
          48,
        );
        final settingsRectSafe = Rect.fromLTWH(
          screenSize.width - (pad.right + 72 + 48),
          topBarY,
          48,
          48,
        );
        final commandRectSafe = Rect.fromLTWH(
          screenSize.width - (pad.right + 124 + 48),
          topBarY,
          48,
          48,
        );
        final rotateRectSafe = Rect.fromLTWH(
          screenSize.width - (pad.right + 176 + 48),
          topBarY,
          48,
          48,
        );

        final hotbarToggleRect = Rect.fromLTWH(
          pad.left + 20,
          topBarY,
          hotbarToggleSize,
          hotbarToggleSize,
        );
        final hotbarPanelWidth = isPortrait
            ? ((hotbarButtonSize * 3) + (hotbarGap * 2) + 16)
            : ((hotbarButtonSize * 9) + (hotbarGap * 8) + 16);
        final hotbarPanelHeight = isPortrait
            ? hotbarPanelWidth
            : (hotbarButtonSize + 16);
        final hotbarPanelRect = Rect.fromLTWH(
          pad.left + 20,
          topBarY + hotbarToggleSize + 8,
          hotbarPanelWidth,
          hotbarPanelHeight,
        );

        final safeAreaExclusions = <Rect>[
          if (pad.top > 0) Rect.fromLTWH(0, 0, screenSize.width, pad.top),
          if (pad.bottom > 0)
            Rect.fromLTWH(
              0,
              screenSize.height - pad.bottom,
              screenSize.width,
              pad.bottom,
            ),
          if (pad.left > 0) Rect.fromLTWH(0, 0, pad.left, screenSize.height),
          if (pad.right > 0)
            Rect.fromLTWH(
              screenSize.width - pad.right,
              0,
              pad.right,
              screenSize.height,
            ),
        ];

        final shouldSend =
            _lastIsPortrait != isPortrait ||
            _lastScreenSize == null ||
            (_lastScreenSize!.width - screenSize.width).abs() > 10 ||
            (_lastScreenSize!.height - screenSize.height).abs() > 10;
        _lastIsPortrait = isPortrait;
        _lastScreenSize = screenSize;
        if (shouldSend && state.shouldStreamVideo) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted && _session.state.shouldStreamVideo) {
              _restartStream();
            }
          });
        }

        final showTouchControls = _supportedPlatform;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              if (state.shouldShowVideo && _session.textureId != null)
                Center(child: _buildTextureWithAspectRatio(pad)),
              if (state.shouldShowHibernation)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bedtime,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: state.videoStateMessage
                                  .split('\n')
                                  .map(
                                    (line) => Text(
                                      line,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (state.shouldShowWaiting)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.bedtime,
                              color: Colors.white,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Waiting for video stream...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (showTouchControls && state.shouldShowVideo)
                LookPad(
                  excludedRegions: [
                    ...safeAreaExclusions,
                    joystickRect,
                    jumpRect,
                    shiftRect,
                    hotbarToggleRect,
                    if (_hotbarExpanded) hotbarPanelRect,
                    closeRectSafe,
                    settingsRectSafe,
                    commandRectSafe,
                    rotateRectSafe,
                  ],
                  invertY: _settings.invertLookY,
                  onDelta: (yaw, pitch) => widget.proxy.sendCommand({
                    'type': 'LOOK_DELTA',
                    'yaw': yaw,
                    'pitch': pitch,
                  }),
                  onTap: (pos) =>
                      widget.proxy.sendCommand({'type': 'CLICK', 'button': 0}),
                  onLongPress: (pos) {
                    HapticFeedback.heavyImpact();
                    widget.proxy.sendCommand({'type': 'CLICK', 'button': 1});
                  },
                ),
              if (showTouchControls && state.shouldShowVideo)
                Positioned(
                  top: topBarY,
                  left: pad.left + 20,
                  child: HotbarToggleButton(
                    size: hotbarToggleSize,
                    expanded: _hotbarExpanded,
                    onPressed: () =>
                        setState(() => _hotbarExpanded = !_hotbarExpanded),
                  ),
                ),
              if (showTouchControls && _hotbarExpanded && state.shouldShowVideo)
                Positioned(
                  top: topBarY + hotbarToggleSize + 8,
                  left: pad.left + 20,
                  child: HotbarGrid(
                    buttonSize: hotbarButtonSize,
                    gap: hotbarGap,
                    selectedSlot: _selectedHotbarSlot,
                    singleRow: !isPortrait,
                    onSelect: (slot) {
                      setState(() {
                        _selectedHotbarSlot = slot;
                        _hotbarExpanded = false;
                      });
                      widget.proxy.sendCommand({
                        'type': 'HOTBAR_SELECT',
                        'slot': slot,
                      });
                    },
                  ),
                ),
              Positioned(
                top: topBarY,
                right: pad.right + 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _closeScreen,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 72,
                child: IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: _openSettings,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 124,
                child: IconButton(
                  icon: const Icon(Icons.code, color: Colors.white),
                  onPressed: _openCommandPalette,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 176,
                child: IconButton(
                  icon: const Icon(Icons.screen_rotation, color: Colors.white),
                  onPressed: _toggleOrientation,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 228,
                child: IconButton(
                  icon: const Icon(Icons.chat, color: Colors.white),
                  onPressed: _openChatScreen,
                ),
              ),
              if (showTouchControls && state.shouldShowVideo)
                SafeArea(
                  child: Stack(
                    children: [
                      Positioned(
                        left: 16,
                        bottom: 16,
                        child: VirtualJoystick(
                          size: joystickSize,
                          onChanged: _input.updateMoveVector,
                        ),
                      ),
                      Positioned(
                        right: 16,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            JumpButton(
                              size: jumpSize,
                              onChanged: _input.setJumpPressed,
                            ),
                            const SizedBox(height: buttonGap),
                            ShiftButton(
                              size: shiftSize,
                              onChanged: _input.setShiftPressed,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
