import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:monkeycraft_client/services/game_input_controller.dart';
import 'package:monkeycraft_client/services/hibernation_models.dart';
import 'package:monkeycraft_client/services/ios_timed_notification_scheduler.dart';
import 'package:monkeycraft_client/services/notification_models.dart';
import 'package:monkeycraft_client/services/stream_proxy.dart';
import 'package:monkeycraft_client/services/hardware_h264_decoder.dart';
import 'package:monkeycraft_client/services/live_activity_service.dart';
import 'package:monkeycraft_client/services/stream_resolution.dart';
import 'package:monkeycraft_client/services/stream_settings.dart';
import 'package:monkeycraft_client/services/timed_notification_coordinator.dart';
import 'package:monkeycraft_client/services/timed_notification_service.dart';
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
  HardwareH264Decoder? _decoder;
  late final GameInputController _input;
  late final TimedNotificationCoordinator _timedCoordinator;
  late final IosTimedNotificationScheduler _timedScheduler;
  late final StreamSettingsStore _settingsStore;
  final _liveActivityService = LiveActivityService();
  bool _hotbarExpanded = false;
  int _selectedHotbarSlot = 0;
  StreamSettings _settings = StreamSettings.defaults;
  StreamSubscription<TimedNotification>? _timedSub;
  StreamSubscription<NudgeNotification>? _nudgeSub;
  StreamSubscription<HibernationEvent>? _hibernationSub;
  StreamSubscription<CommandDeniedEvent>? _commandDeniedSub;
  StreamSubscription<ServerDisconnectEvent>? _serverDisconnectSub;
  int? _textureId;
  StreamSubscription<Uint8List>? _accessUnitSub;
  TimedNotification? _pendingNotification;
  Timer? _notificationCheckTimer;
  bool? _lastIsPortrait;
  bool _restarting = false;
  bool _closing = false;
  bool _foreground = true;
  bool _reconnecting = false;
  bool _hibernating = false;
  String _hibernationMessage = '';
  String? _server;
  String? _password;
  bool? _forcedOrientation;
  int _streamWidth = 0;
  int _streamHeight = 0;
  StreamResolution? _pendingResolution;

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
    _loadStreamSettings();
    _liveActivityService.init();
    _attachProxyStreams();
    _loadReconnectCredentials();

    // Start notification checker timer (runs every second)
    _notificationCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkNotificationTime();
    });

    if (_supportedPlatform) {
      _initHardwareDecoder().then((_) {
        if (mounted) _restartStream();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restartStream();
      });
    }
  }

  void _attachProxyStreams() {
    _timedSub?.cancel();
    _timedSub = widget.proxy.timedNotifications.listen(
      _handleTimedNotification,
    );
    _nudgeSub?.cancel();
    _nudgeSub = widget.proxy.nudges.listen(_handleNudge);
    _hibernationSub?.cancel();
    _hibernationSub = widget.proxy.hibernationEvents.listen(
      _handleHibernationEvent,
    );
    _commandDeniedSub?.cancel();
    _commandDeniedSub = widget.proxy.commandDeniedEvents.listen(
      _handleCommandDenied,
    );
    _serverDisconnectSub?.cancel();
    _serverDisconnectSub = widget.proxy.serverDisconnectEvents.listen(
      _handleServerDisconnect,
    );
  }

  void _handleTimedNotification(TimedNotification notification) {
    // This handles both TIMED and TIMED_STATUS messages
    // Store notification (replacing any previous one)
    _pendingNotification = notification;

    // Schedule with OS for when app is inactive
    _timedCoordinator.handle(notification);

    // Start Live Activity countdown on iOS 16.1+
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

    // Check immediately if it should have already fired
    _checkNotificationTime();
  }

  void _checkNotificationTime() {
    if (!_foreground) return; // Only check when app is active

    final pending = _pendingNotification;
    if (pending == null || pending.fireAtEpochMs == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (pending.fireAtEpochMs! <= now) {
      _showNotificationNow(pending);
      _pendingNotification = null; // Clear pending notification
      _liveActivityService.cancel(); // Dismiss live activity when timer fires
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
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
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
    Navigator.of(context).pop();
  }

  void _handleHibernationEvent(HibernationEvent event) {
    if (event is HibernationStatus) {
      if (event.active) {
        _enterHibernation(event.message ?? _hibernationMessage);
      } else {
        _exitHibernation();
      }
    }
  }

  Future<void> _enterHibernation(String message) async {
    if (_hibernating && message == _hibernationMessage) return;
    _hibernationMessage = message;
    if (!_hibernating && mounted) {
      setState(() => _hibernating = true);
    } else if (mounted) {
      setState(() {});
    }

    _input.releaseAll();
    widget.proxy.sendCommand({'type': 'STOP_STREAM'});

    await _pauseVideoPipeline();
  }

  Future<void> _exitHibernation() async {
    if (!_hibernating) return;
    if (mounted) {
      setState(() => _hibernating = false);
    }
    await _restartStream();
    _refreshVideo();
  }

  void _refreshVideo() {
    _decoder?.reset();
    widget.proxy.requestKeyframe();
  }

  Future<void> _openChatScreen() async {
    _input.releaseAll();
    widget.proxy.sendCommand({'type': 'STOP_STREAM'});
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => ChatScreen(proxy: widget.proxy)),
    );

    if (!mounted) return;
    await _restartStream();
  }

  Future<void> _pauseVideoPipeline() async {
    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    if (mounted) {
      setState(() {
        _textureId = null;
      });
    } else {
      _textureId = null;
    }

    final decoder = _decoder;
    _decoder = null;
    await decoder?.dispose();
  }

  Future<void> _loadReconnectCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _server = prefs.getString('server') ?? '127.0.0.1:9600';
    _password = prefs.getString('password') ?? '';
  }

  Future<void> _loadStreamSettings() async {
    final settings = await _settingsStore.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  void _handleNudge(NudgeNotification nudge) {
    if (!_foreground) return;
    final title = nudge.title ?? 'MonkeyCraft';
    final body = nudge.body ?? '';
    _timedScheduler.showImmediate(title, body, nudge.sound);
    if (nudge.sound) {
      _timedScheduler.playNotificationSound();
    }
    if (!mounted) return;
    final text = body.isEmpty ? title : '$title\n$body';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _initHardwareDecoder() async {
    final decoder = HardwareH264Decoder();
    final textureId = await decoder.createDecoder(fps: _settings.fps);
    _decoder = decoder;
    if (mounted) {
      setState(() => _textureId = textureId);
    }
    _accessUnitSub = widget.proxy.accessUnits.listen((data) {
      _decoder?.pushAccessUnit(data);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.releaseAll();
    _accessUnitSub?.cancel();
    _timedSub?.cancel();
    _nudgeSub?.cancel();
    _hibernationSub?.cancel();
    _commandDeniedSub?.cancel();
    _serverDisconnectSub?.cancel();
    _notificationCheckTimer?.cancel();
    _decoder?.dispose().catchError((_) {});
    _liveActivityService.dispose();
    widget.proxy.stop();
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      _resumeIfNeeded();
      // Check immediately when app resumes (in case notification fired while in background)
      _checkNotificationTime();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _foreground = false;
      _pauseStreaming();
    }
  }

  Future<void> _pauseStreaming() async {
    if (_closing) return;
    _input.releaseAll();
    widget.proxy.sendCommand({'type': 'STOP_STREAM'});

    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _timedSub?.cancel();
    _timedSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;
    await _hibernationSub?.cancel();
    _hibernationSub = null;

    final decoder = _decoder;
    _decoder = null;
    await decoder?.dispose();

    await widget.proxy.stop();
  }

  Future<void> _resumeIfNeeded() async {
    if (_closing || _reconnecting) return;
    if (!mounted) return;
    final server = _server;
    final password = _password;
    if (server == null || password == null) return;

    _reconnecting = true;
    try {
      await widget.proxy.start(server, password);
      widget.proxy.sendPing();
      _attachProxyStreams();
      if (_supportedPlatform) {
        await _initHardwareDecoder();
      }
      _lastIsPortrait = null;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!_hibernating) {
        await _restartStream();
      }
    } catch (_) {
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _closeScreen() async {
    if (_closing) return;
    _closing = true;

    _input.releaseAll();
    widget.proxy.sendCommand({'type': 'STOP_STREAM'});
    SystemChrome.setPreferredOrientations([]);

    await _accessUnitSub?.cancel();
    _accessUnitSub = null;
    await _timedSub?.cancel();
    _timedSub = null;
    await _nudgeSub?.cancel();
    _nudgeSub = null;

    final decoder = _decoder;
    _decoder = null;
    await decoder?.dispose();

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
    if (_streamWidth <= 0 || _streamHeight <= 0) {
      return Padding(
        padding: pad,
        child: SizedBox.expand(child: Texture(textureId: _textureId!)),
      );
    }
    final mq = MediaQuery.of(context);
    final availableWidth = mq.size.width - pad.left - pad.right;
    final availableHeight = mq.size.height - pad.top - pad.bottom;
    final streamAspect = _streamWidth / _streamHeight;
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
          child: Texture(textureId: _textureId!),
        ),
      ),
    );
  }

  Future<void> _restartStream() async {
    final target = _currentTargetResolution();
    if (_restarting) {
      _pendingResolution = target;
      return;
    }
    if (_hibernating) return;
    _restarting = true;
    _input.releaseAll();
    widget.proxy.sendCommand({'type': 'STOP_STREAM'});
    if (_supportedPlatform) {
      if (_decoder == null) {
        await _initHardwareDecoder();
      } else {
        await _decoder?.reset();
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _streamWidth = target.width;
    _streamHeight = target.height;
    debugPrint(
      'Stream target ${target.width}x${target.height} '
      'fps=${_settings.fps} colorMode=${_settings.colorMode} preset=${_settings.resolutionPreset.name}',
    );
    widget.proxy.sendCommand({
      'type': 'START_STREAM',
      'width': target.width,
      'height': target.height,
      'colorMode': _settings.colorMode,
      'fps': _settings.fps,
    });
    final pending = _pendingResolution;
    _pendingResolution = null;
    if (pending != null) {
      _restarting = false;
      await _restartStream();
      return;
    }
    _restarting = false;
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
    setState(() => _settings = next);
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
    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final showTouchControls = Platform.isIOS || Platform.isAndroid;
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

        final shouldSend = _lastIsPortrait != isPortrait;
        _lastIsPortrait = isPortrait;
        if (shouldSend && !_hibernating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _restartStream();
          });
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Center(
                child: _textureId == null
                    ? const SizedBox.shrink()
                    : _buildTextureWithAspectRatio(pad),
              ),
              if (_hibernating)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Hypersleep',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _hibernationMessage
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
              if (showTouchControls && !_hibernating)
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
                  onTap: (pos) {
                    widget.proxy.sendCommand({'type': 'CLICK', 'button': 0});
                  },
                  onLongPress: (pos) {
                    HapticFeedback.heavyImpact();
                    widget.proxy.sendCommand({'type': 'CLICK', 'button': 1});
                  },
                ),
              if (showTouchControls && !_hibernating)
                Positioned(
                  top: topBarY,
                  left: pad.left + 20,
                  child: HotbarToggleButton(
                    size: hotbarToggleSize,
                    expanded: _hotbarExpanded,
                    onPressed: () {
                      setState(() => _hotbarExpanded = !_hotbarExpanded);
                    },
                  ),
                ),
              if (showTouchControls && _hotbarExpanded && !_hibernating)
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
                  icon: Icon(
                    _forcedOrientation == true
                        ? Icons.stay_current_portrait
                        : (_forcedOrientation == false
                              ? Icons.stay_current_landscape
                              : Icons.screen_rotation),
                    color: Colors.white,
                  ),
                  onPressed: _toggleOrientation,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 228,
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _refreshVideo,
                ),
              ),
              Positioned(
                top: topBarY,
                right: pad.right + 280,
                child: IconButton(
                  icon: const Icon(Icons.chat, color: Colors.white),
                  onPressed: _openChatScreen,
                ),
              ),
              if (showTouchControls && !_hibernating)
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
