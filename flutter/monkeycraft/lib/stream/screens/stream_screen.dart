import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/stream/game_input_controller.dart';
import 'package:monkeycraft_client/notifications/ios_timed_notification_scheduler.dart';
import 'package:monkeycraft_client/notifications/notification_models.dart';
import 'package:monkeycraft_client/shared/protocol_models.dart';
import 'package:monkeycraft_client/stream/stream_proxy.dart';
import 'package:monkeycraft_client/stream/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/notifications/live_activity_service.dart';
import 'package:monkeycraft_client/stream/stream_resolution.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';
import 'package:monkeycraft_client/notifications/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/notifications/timed_notification_service.dart';
import 'package:monkeycraft_client/stream/session_controller.dart';
import 'package:monkeycraft_client/stream/screens/stream_settings_screen.dart';
import 'package:monkeycraft_client/chat/chat_screen.dart';
import 'package:monkeycraft_client/stream/widgets/hotbar_selector.dart';
import 'package:monkeycraft_client/stream/widgets/jump_button.dart';
import 'package:monkeycraft_client/stream/widgets/look_pad.dart';
import 'package:monkeycraft_client/stream/widgets/shift_button.dart';
import 'package:monkeycraft_client/stream/widgets/virtual_joystick.dart';
import 'package:monkeycraft_client/stream/widgets/screen_controls.dart';
import 'package:monkeycraft_client/stream/widgets/stream_overlays.dart';
import 'package:monkeycraft_client/stream/widgets/command_palette.dart';
import 'package:monkeycraft_client/map/map_screen.dart';
import 'package:monkeycraft_client/serverpicker/server_picker_screen.dart';

class StreamScreen extends StatefulWidget {
  final StreamProxy proxy;
  final String server;
  final String password;

  const StreamScreen({
    super.key,
    required this.proxy,
    required this.server,
    required this.password,
  });

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
  bool _isScreenOpen = false;
  bool _screenControlsExpanded = false;
  Offset _screenControlPosition = const Offset(
    double.infinity,
    double.infinity,
  );
  ClickMode _clickMode = ClickMode.left;
  bool _shiftActive = false;

  StreamSubscription<NudgeNotification>? _nudgeSub;
  StreamSubscription<DateTime>? _heartbeatAckSub;
  StreamSubscription<CommandDeniedEvent>? _commandDeniedSub;
  StreamSubscription<ServerDisconnectEvent>? _serverDisconnectSub;
  StreamSubscription<Uint8List>? _accessUnitSub;
  StreamSubscription<SessionState>? _sessionStateSub;
  StreamSubscription<void>? _connectionLostSub;
  StreamSubscription<void>? _connectionRestoredSub;
  StreamSubscription<bool>? _screenStateSub;
  StreamSubscription<WorldState>? _worldStateSub;

  Timer? _notificationCheckTimer;
  bool? _lastIsPortrait;
  Size? _lastScreenSize;
  bool _closing = false;
  bool _handingOff = false;
  bool? _forcedOrientation;

  AppLifecycleState? _lastLifecycleState;
  bool _isProcessingLifecycle = false;

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
    _session.setCredentials(widget.server, widget.password);
    _attachProxyStreams();
    _attachSessionState();

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
      _session.resetReconnectionState();
    });
    _connectionLostSub?.cancel();
    _connectionLostSub = widget.proxy.connectionLostEvents.listen((_) {
      _handleConnectionLost();
    });
    _connectionRestoredSub?.cancel();
    _connectionRestoredSub = widget.proxy.connectionRestoredEvents.listen((_) {
      _onConnectionRestored();
    });
    _screenStateSub?.cancel();
    _screenStateSub = widget.proxy.screenStateEvents.listen((isOpen) {
      if (mounted) setState(() => _isScreenOpen = isOpen);
    });
    _isScreenOpen = widget.proxy.screenOpen;
    _worldStateSub?.cancel();
    _worldStateSub = widget.proxy.worldStateEvents.listen(_handleWorldState);
  }

  void _attachSessionState() {
    _sessionStateSub?.cancel();
    _sessionStateSub = _session.stateStream.listen((state) {
      if (state.shouldReturnToLogin && !_closing) {
        _closeScreenAndReturnToLogin();
        return;
      }

      if (mounted) setState(() {});

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
    _input.releaseAll();
    await _pauseVideoPipeline();

    if (_session.shouldAutoNavigateToChat && mounted) {
      await _openChatScreenAuto();
    }
  }

  Future<void> _handleExitHibernation() async {
    if (!mounted) return;
    await _restartStream();
    _session.refreshVideo();
  }

  void _handleConnectionLost() {
    if (_closing) return;
    _session.handleConnectionLost();
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

    await _session.disposeDecoder();
    _session.dispose();
    _liveActivityService.dispose();
    await widget.proxy.stop();
    await openAudioMcService.disconnect();
    await mcParksV1Service.disconnect();

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
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

  void _handleWorldState(WorldState worldState) {
    if (_closing || _handingOff) return;
    // The player left the world (back to a menu) on the Minecraft client side;
    // hand the still-open connection back to the server picker.
    if (worldState.phase == WorldPhase.menu) {
      _goToServerPicker();
    }
  }

  void _goToServerPicker() {
    if (_closing || _handingOff || !mounted) return;
    _handingOff = true;
    _input.releaseAll();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ServerPickerScreen(
          proxy: widget.proxy,
          server: widget.server,
          password: widget.password,
        ),
      ),
    );
  }

  Future<void> _pauseVideoPipeline() async {
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _session.disposeDecoder();
  }

  void _syncClientStatus() {
    final resolution = _currentTargetResolution();
    _session.syncStatus(resolution: resolution);
  }

  Future<void> _openChatScreenAuto() async {
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

    if (!mounted) return;
    // Switch back to streaming mode
    _session.setMode(
      ClientMode.streaming,
      resolution: _currentTargetResolution(),
    );

    if (_session.state.videoState == VideoState.active) {
      await _restartStream();
    }
  }

  Future<void> _openChatScreen() async {
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

    if (!mounted) return;
    _session.setMode(
      ClientMode.streaming,
      resolution: _currentTargetResolution(),
    );
    await _restartStream();
  }

  Future<void> _openMapScreen() async {
    // Keep decoder and access unit subscription alive — map mode streams video too
    _session.setMode(ClientMode.map, resolution: _currentTargetResolution());
    _input.releaseAll();

    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MapScreen(proxy: widget.proxy, session: _session),
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

    if (!mounted) return;
    _session.setMode(
      ClientMode.streaming,
      resolution: _currentTargetResolution(),
    );
    // Decoder stayed alive, just re-sync the mode
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
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;

    final decoder = HardwareH264Decoder();
    final textureId = await decoder.createDecoder(fps: _settings.fps);
    _session.decoder = decoder;
    _session.textureId = textureId;

    _accessUnitSub = widget.proxy.accessUnits.listen((data) {
      _session.handleAccessUnit(
        data,
        frameWidth: widget.proxy.lastFrameWidth,
        frameHeight: widget.proxy.lastFrameHeight,
      );
    });
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
    _connectionRestoredSub?.cancel();
    _screenStateSub?.cancel();
    _worldStateSub?.cancel();
    _notificationCheckTimer?.cancel();
    _session.disposeDecoder();
    _session.dispose();
    _liveActivityService.dispose();
    // Keep the connection alive when handing off to the server picker.
    if (!_handingOff) widget.proxy.stop();
    SystemChrome.setPreferredOrientations([]);
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
          _session.setForeground(true);
          await _resumeIfNeeded();
        } else if (currentState == AppLifecycleState.inactive ||
            currentState == AppLifecycleState.paused ||
            currentState == AppLifecycleState.detached) {
          _session.setForeground(false);
          await _pauseStreaming();
        }
      } catch (e) {
        debugPrint('StreamScreen lifecycle error: $e');
      }
    }
    _isProcessingLifecycle = false;
  }

  Future<void> _pauseStreaming() async {
    if (_closing) {
      return;
    }
    _input.releaseAll();
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;
    await _heartbeatAckSub?.cancel();
    _heartbeatAckSub = null;
    await _session.disposeDecoder();
    await widget.proxy.stop();
  }

  Future<void> _onConnectionRestored() async {
    if (!mounted || _closing) return;
    _session.updateConnectionState(true);
    _session.reattachToProxy();
    _attachProxyStreams();
    if (_supportedPlatform) {
      await _initHardwareDecoder();
    }
    if (!mounted) return;
    _lastIsPortrait = null;
    _session.resetFrameTime();
    _syncClientStatus();
  }

  Future<void> _resumeIfNeeded() async {
    if (_closing || !mounted) {
      return;
    }
    if (widget.proxy.isConnected) return;

    await _session.resumeConnection();
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
    await openAudioMcService.disconnect();
    await mcParksV1Service.disconnect();

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
      return;
    }
    await _session.restartStream(target, onDecoderNeeded: _initHardwareDecoder);

    // Ensure subscription is set up even if decoder was reused
    if (_session.decoder != null && _accessUnitSub == null) {
      _accessUnitSub = widget.proxy.accessUnits.listen((data) {
        _session.handleAccessUnit(
          data,
          frameWidth: widget.proxy.lastFrameWidth,
          frameHeight: widget.proxy.lastFrameHeight,
        );
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
    await showCommandPalette(context: context, proxy: widget.proxy);
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
                  Text(
                    'Unsupported platform',
                    style: appSettings.textStyleWithFont(
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This client supports iOS and Android only.',
                    style: appSettings.textStyleWithFont(
                      const TextStyle(color: Colors.white70),
                    ),
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

        final sw = _session.streamWidth;
        final sh = _session.streamHeight;
        Rect videoDisplayRect = Rect.zero;
        if (sw > 0 && sh > 0) {
          final availableWidth = safeW;
          final availableHeight = safeH;
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
          final offsetX = pad.left + (availableWidth - displayWidth) / 2;
          final offsetY = pad.top + (availableHeight - displayHeight) / 2;
          videoDisplayRect = Rect.fromLTWH(
            offsetX,
            offsetY,
            displayWidth,
            displayHeight,
          );
        }

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
                HibernationOverlay(message: state.videoStateMessage),
              if (state.shouldShowWaiting) const WaitingOverlay(),
              if (state.isReconnecting)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Reconnecting...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              if (state.shouldShowResolutionMismatch)
                ResolutionMismatchOverlay(
                  message: state.resolutionMismatchMessage,
                ),
              if (showTouchControls && state.shouldShowVideo && _isScreenOpen)
                ScreenTouchHandler(
                  proxy: widget.proxy,
                  clickMode: _clickMode,
                  shiftActive: _shiftActive,
                  videoDisplayRect: videoDisplayRect,
                ),
              if (showTouchControls && state.shouldShowVideo && !_isScreenOpen)
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
                    onKey: !_isScreenOpen
                        ? (key) {
                            widget.proxy.sendCommand({
                              'type': 'INPUT',
                              'key': key,
                              'pressed': true,
                            });
                            Future.delayed(
                              const Duration(milliseconds: 50),
                              () {
                                widget.proxy.sendCommand({
                                  'type': 'INPUT',
                                  'key': key,
                                  'pressed': false,
                                });
                              },
                            );
                          }
                        : null,
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
              Positioned(
                top: topBarY,
                right: pad.right + 280,
                child: IconButton(
                  icon: const Icon(Icons.map, color: Colors.white),
                  onPressed: _openMapScreen,
                ),
              ),
              if (showTouchControls && state.shouldShowVideo && !_isScreenOpen)
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
              if (showTouchControls &&
                  state.shouldShowVideo &&
                  _isScreenOpen) ...[
                ScreenControlToggle(
                  expanded: _screenControlsExpanded,
                  onToggle: () => setState(
                    () => _screenControlsExpanded = !_screenControlsExpanded,
                  ),
                  position: _screenControlPosition,
                  onPositionChanged: (pos) =>
                      setState(() => _screenControlPosition = pos),
                  screenSize: screenSize,
                  safePadding: pad,
                ),
                if (_screenControlsExpanded)
                  SmartPalettePosition(
                    togglePosition: _screenControlPosition,
                    toggleSize: kToggleSize,
                    screenSize: screenSize,
                    safePadding: pad,
                    child: ScreenControlPalette(
                      onEsc: () {
                        setState(() => _screenControlsExpanded = false);
                        widget.proxy.sendScreenKey('ESCAPE', true);
                      },
                      shiftActive: _shiftActive,
                      onShiftToggle: () {
                        setState(() => _shiftActive = !_shiftActive);
                        widget.proxy.sendScreenModifier('SHIFT', _shiftActive);
                      },
                      clickMode: _clickMode,
                      onClickModeChange: (mode) =>
                          setState(() => _clickMode = mode),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
