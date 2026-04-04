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
  static const AppFont defaultFont = AppFont.mulish;

  AppFont _font = defaultFont;
  AppFont get font => _font;

  String? _chatBackgroundPath;
  String? get chatBackgroundPath => _chatBackgroundPath;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_kFont) ?? defaultFont.index;
    _font = AppFont.values[index.clamp(0, AppFont.values.length - 1)];

    final bgPath = prefs.getString(_kChatBackground);
    if (bgPath != null && File(bgPath).existsSync()) {
      _chatBackgroundPath = bgPath;
    }

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

  TextStyle textStyleWithFont(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(fontFamily: _font.familyName);
  }
}
