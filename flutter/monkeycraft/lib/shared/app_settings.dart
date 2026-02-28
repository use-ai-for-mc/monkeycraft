import 'package:flutter/material.dart';
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
  static const AppFont defaultFont = AppFont.mulish;

  AppFont _font = defaultFont;
  AppFont get font => _font;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final index = prefs.getInt(_kFont) ?? defaultFont.index;
    _font = AppFont.values[index.clamp(0, AppFont.values.length - 1)];
    notifyListeners();
  }

  Future<void> setFont(AppFont font) async {
    if (_font == font) return;
    _font = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kFont, font.index);
    notifyListeners();
  }

  TextStyle textStyleWithFont(TextStyle? base) {
    return (base ?? const TextStyle()).copyWith(fontFamily: _font.familyName);
  }
}
