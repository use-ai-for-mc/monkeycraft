import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:monkeycraft_client/main.dart';
import 'package:monkeycraft_client/shared/app_settings.dart';
import 'package:monkeycraft_client/stream/stream_settings.dart';

class StreamSettingsScreen extends StatefulWidget {
  final StreamSettings initial;

  const StreamSettingsScreen({super.key, required this.initial});

  @override
  State<StreamSettingsScreen> createState() => _StreamSettingsScreenState();
}

class _StreamSettingsScreenState extends State<StreamSettingsScreen> {
  late StreamSettings _settings;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
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
        ],
      ),
    );
  }
}
