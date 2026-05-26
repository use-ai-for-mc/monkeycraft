import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_kFont) ?? defaultFont.index;
    _font = AppFont.values[index.clamp(0, AppFont.values.length - 1)];

    final bgPath = prefs.getString(_kChatBackground);
    if (bgPath != null && File(bgPath).existsSync()) {
      _chatBackgroundPath = bgPath;
    }

    _mcParksVolume = (prefs.getDouble(_kMcParksVolume) ?? defaultMcParksVolume)
        .clamp(0.0, 1.0);

    _keepTemporaryBanner = prefs.getBool(_kKeepTemporaryBanner) ?? false;

    notifyListeners();
  }

  Future<void> setFont(AppFont font) async {
    if (_font == font) return;
    _font = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFont, font.index);
    notifyListeners();
  }

  Future<void> setChatBackground(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/chat_background.jpg');
    await File(sourcePath).copy(dest.path);
    _chatBackgroundPath = dest.path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kChatBackground, dest.path);
    notifyListeners();
  }

  Future<void> clearChatBackground() async {
    if (_chatBackgroundPath != null) {
      final file = File(_chatBackgroundPath!);
      if (file.existsSync()) {
        await file.delete();
      }
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

  TextStyle textStyleWithFont(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(fontFamily: _font.familyName);
  }
}
