import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:monkeycraft_client/platform/local_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppFont { mulish, montserrat, nunitoSans }

extension AppFontDisplay on AppFont {
  String get displayName {
    switch (this) {
      case AppFont.mulish:
        return 'Mulish';
      case AppFont.montserrat:
        return 'Montserrat';
      case AppFont.nunitoSans:
        return 'Nunito Sans';
    }
  }

  String get familyName {
    switch (this) {
      case AppFont.mulish:
        return 'Mulish';
      case AppFont.montserrat:
        return 'Montserrat';
      case AppFont.nunitoSans:
        return 'NunitoSans';
    }
  }
}

class AppSettings extends ChangeNotifier {
  static const _kFont = 'app_font';
  static const _kChatBackground = 'app_chat_background';
  static const _kMcParksVolume = 'mcparks_volume';
  static const _kKeepTemporaryBanner = 'notif_keep_temporary_banner';
  static const _kPhoneName = 'phone_name';
  static const AppFont defaultFont = AppFont.mulish;
  static const double defaultMcParksVolume = 0.5;

  AppFont _font = defaultFont;
  AppFont get font => _font;

  String? _chatBackgroundPath;
  String? get chatBackgroundPath => _chatBackgroundPath;

  double _mcParksVolume = defaultMcParksVolume;
  double get mcParksVolume => _mcParksVolume;

  bool _keepTemporaryBanner = false;
  bool get keepTemporaryBanner => _keepTemporaryBanner;

  String? _phoneNameOverride;
  String? get phoneNameOverride => _phoneNameOverride;

  String _deviceModel = '';
  String get deviceModel => _deviceModel;

  String get phoneName {
    final override = _phoneNameOverride;
    if (override != null && override.isNotEmpty) return override;
    return _deviceModel.isEmpty ? 'This phone' : _deviceModel;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_kFont) ?? defaultFont.index;
    _font = AppFont.values[index.clamp(0, AppFont.values.length - 1)];

    final bgPath = prefs.getString(_kChatBackground);
    if (bgPath != null && localFileExists(bgPath)) {
      _chatBackgroundPath = bgPath;
    }

    _mcParksVolume = (prefs.getDouble(_kMcParksVolume) ?? defaultMcParksVolume)
        .clamp(0.0, 1.0);

    _keepTemporaryBanner = prefs.getBool(_kKeepTemporaryBanner) ?? false;

    final savedPhoneName = prefs.getString(_kPhoneName)?.trim();
    _phoneNameOverride = (savedPhoneName == null || savedPhoneName.isEmpty)
        ? null
        : savedPhoneName;
    _deviceModel = await _detectDeviceModel();

    notifyListeners();
  }

  static Future<String> _detectDeviceModel() async {
    try {
      final info = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await info.webBrowserInfo;
        return web.browserName.name;
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          final ios = await info.iosInfo;
          final name = ios.name.trim();
          return name.isNotEmpty ? name : ios.utsname.machine;
        case TargetPlatform.android:
          final android = await info.androidInfo;
          return '${android.manufacturer} ${android.model}'.trim();
        case TargetPlatform.macOS:
          final mac = await info.macOsInfo;
          final name = mac.computerName.trim();
          return name.isNotEmpty ? name : mac.model;
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> setFont(AppFont font) async {
    if (_font == font) return;
    _font = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFont, font.index);
    notifyListeners();
  }

  Future<void> setChatBackground(String sourcePath) async {
    final destPath = await persistLocalFile(sourcePath, 'chat_background.jpg');
    if (destPath == null) return;
    _chatBackgroundPath = destPath;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kChatBackground, destPath);
    notifyListeners();
  }

  Future<void> clearChatBackground() async {
    if (_chatBackgroundPath != null) {
      await deleteLocalFile(_chatBackgroundPath!);
    }
    _chatBackgroundPath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kChatBackground);
    notifyListeners();
  }

  Future<void> setMcParksVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if (_mcParksVolume == clamped) return;
    _mcParksVolume = clamped;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kMcParksVolume, clamped);
    notifyListeners();
  }

  Future<void> setKeepTemporaryBanner(bool value) async {
    if (_keepTemporaryBanner == value) return;
    _keepTemporaryBanner = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeepTemporaryBanner, value);
    notifyListeners();
  }

  Future<void> setPhoneName(String value) async {
    final trimmed = value.trim();
    final next = trimmed.isEmpty ? null : trimmed;
    if (_phoneNameOverride == next) return;
    _phoneNameOverride = next;
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_kPhoneName);
    } else {
      await prefs.setString(_kPhoneName, next);
    }
    notifyListeners();
  }

  static const List<String> emojiFallbackFamilies = [
    'Noto Color Emoji',
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Sans Symbols 2',
  ];

  TextStyle textStyleWithFont(TextStyle? base) {
    final style = base ?? const TextStyle();
    return style.copyWith(
      fontFamily: _font.familyName,
      fontFamilyFallback: [
        ...?style.fontFamilyFallback,
        ...emojiFallbackFamilies,
      ],
    );
  }
}
