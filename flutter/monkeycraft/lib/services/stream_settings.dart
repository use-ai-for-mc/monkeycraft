import 'package:shared_preferences/shared_preferences.dart';

enum ResolutionPreset { low, medium, high }

class StreamSettings {
  final int fps;
  final int colorMode;
  final ResolutionPreset resolutionPreset;
  final bool invertLookY;

  const StreamSettings({
    required this.fps,
    required this.colorMode,
    required this.resolutionPreset,
    required this.invertLookY,
  });

  static const StreamSettings defaults = StreamSettings(
    fps: 20,
    colorMode: 0,
    resolutionPreset: ResolutionPreset.high,
    invertLookY: true,
  );

  double get resolutionScale {
    switch (resolutionPreset) {
      case ResolutionPreset.low:
        return 0.5;
      case ResolutionPreset.medium:
        return 0.75;
      case ResolutionPreset.high:
        return 1.0;
    }
  }

  int get maxDim {
    switch (resolutionPreset) {
      case ResolutionPreset.low:
        return 640;
      case ResolutionPreset.medium:
        return 960;
      case ResolutionPreset.high:
        return 1280;
    }
  }

  StreamSettings copyWith({
    int? fps,
    int? colorMode,
    ResolutionPreset? resolutionPreset,
    bool? invertLookY,
  }) {
    return StreamSettings(
      fps: fps ?? this.fps,
      colorMode: colorMode ?? this.colorMode,
      resolutionPreset: resolutionPreset ?? this.resolutionPreset,
      invertLookY: invertLookY ?? this.invertLookY,
    );
  }
}

class StreamSettingsStore {
  static const _kFps = 'stream_fps';
  static const _kColorMode = 'stream_color_mode';
  static const _kResolutionPreset = 'stream_resolution_preset';
  static const _kInvertLookY = 'stream_invert_look_y';

  Future<StreamSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final fps = prefs.getInt(_kFps) ?? StreamSettings.defaults.fps;
    final colorMode =
        prefs.getInt(_kColorMode) ?? StreamSettings.defaults.colorMode;
    final presetIndex =
        prefs.getInt(_kResolutionPreset) ??
        StreamSettings.defaults.resolutionPreset.index;
    final preset = ResolutionPreset
        .values[presetIndex.clamp(0, ResolutionPreset.values.length - 1)];
    final invertLookY =
        prefs.getBool(_kInvertLookY) ?? StreamSettings.defaults.invertLookY;
    return StreamSettings(
      fps: fps,
      colorMode: colorMode,
      resolutionPreset: preset,
      invertLookY: invertLookY,
    );
  }

  Future<void> save(StreamSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFps, settings.fps);
    await prefs.setInt(_kColorMode, settings.colorMode);
    await prefs.setInt(_kResolutionPreset, settings.resolutionPreset.index);
    await prefs.setBool(_kInvertLookY, settings.invertLookY);
  }
}
