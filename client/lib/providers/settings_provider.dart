import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final ThemeMode themeMode;
  final double terminalFontSize;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.terminalFontSize = 14.0,
  });

  AppSettings copyWith({ThemeMode? themeMode, double? terminalFontSize}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      terminalFontSize: terminalFontSize ?? this.terminalFontSize,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('theme_mode') ?? 'system';
    final fontSize = prefs.getDouble('terminal_font_size') ?? 14.0;
    state = AppSettings(
      themeMode: _parseThemeMode(themeName),
      terminalFontSize: fontSize,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  Future<void> setTerminalFontSize(double size) async {
    state = state.copyWith(terminalFontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_font_size', size);
  }

  static ThemeMode _parseThemeMode(String name) {
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
