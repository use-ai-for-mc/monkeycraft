import 'package:flutter/material.dart';
import 'package:monkeycraft_client/services/stream_settings.dart';

class StreamSettingsScreen extends StatefulWidget {
  final StreamSettings initial;

  const StreamSettingsScreen({super.key, required this.initial});

  @override
  State<StreamSettingsScreen> createState() => _StreamSettingsScreenState();
}

class _StreamSettingsScreenState extends State<StreamSettingsScreen> {
  late StreamSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initial;
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
        ],
      ),
    );
  }
}
