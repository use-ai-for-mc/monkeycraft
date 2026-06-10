import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:monkeycraft_client/audio/mcparks_v1_service.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/notifications/banner_style_settings_tile.dart';
import 'package:monkeycraft_client/shared/app_settings.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';

class StreamSettingsScreen extends StatefulWidget {
  final StreamSettings initial;
  final bool dataSaverSupported;

  const StreamSettingsScreen({
    super.key,
    required this.initial,
    this.dataSaverSupported = true,
  });

  @override
  State<StreamSettingsScreen> createState() => _StreamSettingsScreenState();
}

class _StreamSettingsScreenState extends State<StreamSettingsScreen> {
  late StreamSettings _settings;
  Timer? _updateTimer;
  List<McParksActiveTrack> _mcParksTracks = const [];

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      List<McParksActiveTrack> next = const [];
      if (mcParksV1Service.isActive) {
        try {
          next = await mcParksV1Service.snapshotActive();
        } catch (_) {
          // Best-effort; leave previous snapshot in place on transient error.
          if (!mounted) return;
          setState(() {});
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _mcParksTracks = next;
      });
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  static String _humanDuration(Duration d) {
    final s = d.inSeconds.abs();
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final rs = s % 60;
    if (m < 60) return '${m}m ${rs}s';
    final h = m ~/ 60;
    final rm = m % 60;
    return '${h}h ${rm}m';
  }

  static ({String label, Color color}) _badgeFor(McParksActiveTrack t) {
    if (!t.active) return (label: 'STOPPED', color: const Color(0xFF808080));
    if (t.fadingOut) return (label: 'FADING', color: const Color(0xFFF5A623));
    if (t.looping) return (label: 'LOOP', color: const Color(0xFF4FC3F7));
    return (label: 'ONESHOT', color: const Color(0xFFE1BEE7));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Settings'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_settings),
            child: const Text('Apply'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<AppFont>(
            initialValue: appSettings.font,
            decoration: const InputDecoration(labelText: 'Font'),
            items: AppFont.values
                .map(
                  (f) => DropdownMenuItem(value: f, child: Text(f.displayName)),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              appSettings.setFont(v);
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<ResolutionPreset>(
            initialValue: _settings.resolutionPreset,
            decoration: const InputDecoration(labelText: 'Resolution'),
            items: const [
              DropdownMenuItem(value: ResolutionPreset.low, child: Text('Low')),
              DropdownMenuItem(
                value: ResolutionPreset.medium,
                child: Text('Medium'),
              ),
              DropdownMenuItem(
                value: ResolutionPreset.high,
                child: Text('High'),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(
                () => _settings = _settings.copyWith(resolutionPreset: v),
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _settings.colorMode,
            decoration: const InputDecoration(labelText: 'Color Mode'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Normal')),
              DropdownMenuItem(value: 1, child: Text('High Perf (12-bit)')),
              DropdownMenuItem(value: 2, child: Text('Retro (6-bit)')),
              DropdownMenuItem(value: 3, child: Text('Grayscale')),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _settings = _settings.copyWith(colorMode: v));
            },
          ),
          const SizedBox(height: 16),
          Text('FPS: ${_settings.fps}'),
          Slider(
            min: 1,
            max: 20,
            divisions: 19,
            value: _settings.fps.toDouble(),
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(fps: v.round())),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Invert Look Y-Axis'),
            subtitle: const Text(
              'ON: drag up to look down (indirect)\nOFF: drag up to look up (direct)',
            ),
            value: _settings.invertLookY,
            onChanged: (v) =>
                setState(() => _settings = _settings.copyWith(invertLookY: v)),
          ),
          SwitchListTile(
            title: const Text('Auto-switch Ride/Chat'),
            subtitle: const Text(
              'ON: auto-switch to Chat when hypersleep starts, back to Ride when it ends',
            ),
            value: _settings.autoSwitchRideChat,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(autoSwitchRideChat: v),
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-face Movement'),
            subtitle: const Text(
              'Gradually turn player face toward movement direction',
            ),
            value: _settings.autoFaceMovement,
            onChanged: (v) => setState(
              () => _settings = _settings.copyWith(autoFaceMovement: v),
            ),
          ),
          SwitchListTile(
            title: const Text('Data Saver'),
            subtitle: Text(
              widget.dataSaverSupported
                  ? 'Send fewer keyframes to roughly halve cellular data. '
                        'Trade-off: slower recovery if frames are dropped on a '
                        'weak connection.'
                  : 'Not supported by this server — update the mod to use it.',
            ),
            value: _settings.dataSaver,
            onChanged: widget.dataSaverSupported
                ? (v) =>
                      setState(() => _settings = _settings.copyWith(dataSaver: v))
                : null,
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('Chat Background'),
            subtitle: Text(
              appSettings.chatBackgroundPath != null ? 'Custom image' : 'Default',
            ),
            trailing: const Icon(Icons.image),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_library),
                        title: const Text('Choose Image'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked != null) {
                            await appSettings.setChatBackground(picked.path);
                            setState(() {});
                          }
                        },
                      ),
                      if (appSettings.chatBackgroundPath != null)
                        ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: const Text('Reset to Default'),
                          onTap: () async {
                            Navigator.pop(ctx);
                            await appSettings.clearChatBackground();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (openAudioMcService.isActive) const Divider(height: 32),
          if (openAudioMcService.isActive)
            ListTile(
              title: const Text('Audio Connection'),
              subtitle: Text(
                openAudioMcService.isConnected
                    ? 'Connected to OpenAudioMc'
                    : 'Connecting...',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await openAudioMcService.disconnect();
                      setState(() {});
                    },
                    child: Text(
                      openAudioMcService.isConnected ? 'Disconnect' : 'Cancel',
                    ),
                  ),
                  if (openAudioMcService.isConnected)
                    TextButton(
                      onPressed: () async {
                        await openAudioMcService.reconnect();
                        setState(() {});
                      },
                      child: const Text('Refresh'),
                    ),
                ],
              ),
            ),
          if (mcParksV1Service.isActive) const Divider(height: 32),
          if (mcParksV1Service.isActive)
            ListTile(
              title: const Text('Audio Connection'),
              subtitle: Text(
                mcParksV1Service.isConnected
                    ? 'Connected to MCParks'
                    : 'Connecting...',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      await mcParksV1Service.disconnect();
                      setState(() {});
                    },
                    child: Text(
                      mcParksV1Service.isConnected ? 'Disconnect' : 'Cancel',
                    ),
                  ),
                  if (mcParksV1Service.isConnected)
                    TextButton(
                      onPressed: () async {
                        await mcParksV1Service.reconnect();
                        setState(() {});
                      },
                      child: const Text('Refresh'),
                    ),
                ],
              ),
            ),
          if (mcParksV1Service.isActive)
            ListenableBuilder(
              listenable: appSettings,
              builder: (context, _) {
                final pct = (appSettings.mcParksVolume * 100).round();
                return ListTile(
                  title: const Text('MCParks Volume'),
                  subtitle: Slider(
                    value: appSettings.mcParksVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 100,
                    label: '$pct%',
                    onChanged: (v) {
                      appSettings.setMcParksVolume(v);
                      mcParksV1Service.setVolume(v);
                    },
                  ),
                  trailing: SizedBox(
                    width: 48,
                    child: Text(
                      '$pct%',
                      textAlign: TextAlign.right,
                    ),
                  ),
                );
              },
            ),
          if (mcParksV1Service.isActive) ..._buildMcParksTrackList(),
          const BannerStyleSettingsTile(),
        ],
      ),
    );
  }

  List<Widget> _buildMcParksTrackList() {
    final now = DateTime.now();
    final count = _mcParksTracks.length;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        count == 0
            ? 'MCParks Active Tracks — nothing playing'
            : 'MCParks Active Tracks — $count active',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    );
    if (count == 0) {
      return [header];
    }
    return [
      header,
      for (final t in _mcParksTracks) _buildTrackTile(t, now),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Tap Stop to fade a specific track over 3s.',
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.5),
          ),
        ),
      ),
    ];
  }

  Widget _buildTrackTile(McParksActiveTrack t, DateTime now) {
    final badge = _badgeFor(t);
    final startedAgo = t.startedAt != null
        ? _humanDuration(now.difference(t.startedAt!))
        : '?';
    final lastTriggeredAgo = t.lastTriggerAt != null
        ? _humanDuration(now.difference(t.lastTriggerAt!))
        : '?';
    final diagnosis = t.diagnose(now);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          t.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badge.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          badge.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: badge.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    final stopped = await mcParksV1Service.stopSoundByName(
                      t.name,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          stopped
                              ? 'Stopped audio: ${t.name}'
                              : 'No active audio named "${t.name}"',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'started $startedAgo ago \u00B7 triggered ${t.triggerCount}\u00D7'
              ' (last: $lastTriggeredAgo ago) \u00B7 vol ${t.serverVolume}%',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.65),
              ),
            ),
            if (diagnosis != null) ...[
              const SizedBox(height: 2),
              Text(
                '\u2192 $diagnosis',
                style: TextStyle(
                  fontSize: 11,
                  color: t.triggerCount > 1 && t.looping
                      ? const Color(0xFFB8860B)
                      : Colors.black.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              'msg: ${t.lastServerMessage}',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.black.withValues(alpha: 0.55),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
