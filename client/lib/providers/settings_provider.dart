import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';

class AppSettings {
  final ThemeMode themeMode;
  final double fontSize;
  final bool terminalCursorBlink;
  final String defaultAgentProvider;
  final String locale;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontSize = 14.0,
    this.terminalCursorBlink = true,
    this.defaultAgentProvider = 'claude-code',
    this.locale = 'zh',
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? fontSize,
    bool? terminalCursorBlink,
    String? defaultAgentProvider,
    String? locale,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      terminalCursorBlink: terminalCursorBlink ?? this.terminalCursorBlink,
      defaultAgentProvider: defaultAgentProvider ?? this.defaultAgentProvider,
      locale: locale ?? this.locale,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final locale = prefs.getString('locale') ?? 'zh';
    S.locale = locale;
    state = AppSettings(
      themeMode: _parseThemeMode(prefs.getString('theme_mode') ?? 'system'),
      fontSize: prefs.getDouble('terminal_font_size') ?? 14.0,
      terminalCursorBlink: prefs.getBool('terminal_cursor_blink') ?? true,
      defaultAgentProvider: prefs.getString('default_agent_provider') ?? 'claude-code',
      locale: locale,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('terminal_font_size', size);
  }

  Future<void> setTerminalCursorBlink(bool blink) async {
    state = state.copyWith(terminalCursorBlink: blink);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('terminal_cursor_blink', blink);
  }

  Future<void> setDefaultAgentProvider(String provider) async {
    state = state.copyWith(defaultAgentProvider: provider);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_agent_provider', provider);
  }

  Future<void> setLocale(String locale) async {
    S.locale = locale;
    state = state.copyWith(locale: locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }

  Future<void> clearSavedServers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_servers');
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
