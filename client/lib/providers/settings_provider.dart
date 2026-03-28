import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/strings.dart';

const _kDefaultBuiltinCommands = [
  {'name': 'help', 'description': 'Show help', 'providers': ''},
  {'name': 'model', 'description': 'Change model', 'providers': 'claude-code'},
  {'name': 'clear', 'description': 'Clear conversation', 'providers': 'claude-code'},
  {'name': 'login', 'description': 'Login', 'providers': 'claude-code'},
  {'name': 'logout', 'description': 'Logout', 'providers': 'claude-code'},
  {'name': 'doctor', 'description': 'Health check', 'providers': 'claude-code'},
  {'name': 'status', 'description': 'Show session status', 'providers': ''},
  {'name': 'permissions', 'description': 'Manage permissions', 'providers': 'claude-code'},
  {'name': 'memory', 'description': 'Memory management', 'providers': 'claude-code'},
  {'name': 'mcp', 'description': 'MCP server management', 'providers': 'claude-code'},
  {'name': 'add-dir', 'description': 'Add directory', 'providers': 'claude-code'},
  {'name': 'compact', 'description': 'Compact conversation', 'providers': 'claude-code'},
  {'name': 'fast', 'description': 'Toggle fast mode', 'providers': 'claude-code'},
  {'name': 'effort', 'description': 'Set effort level', 'providers': 'claude-code'},
  {'name': 'terminal', 'description': 'Open terminal', 'providers': 'claude-code'},
  {'name': 'vim', 'description': 'Vim mode', 'providers': 'claude-code'},
  {'name': 'listen', 'description': 'Listen mode', 'providers': 'claude-code'},
  {'name': 'bug', 'description': 'Report a bug', 'providers': 'claude-code'},
];

class AppSettings {
  final ThemeMode themeMode;
  final double fontSize;
  final bool terminalCursorBlink;
  final String defaultAgentProvider;
  final String locale;
  final List<Map<String, String>> builtinSlashCommands;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.fontSize = 14.0,
    this.terminalCursorBlink = true,
    this.defaultAgentProvider = 'claude-code',
    this.locale = 'zh',
    this.builtinSlashCommands = const [],
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? fontSize,
    bool? terminalCursorBlink,
    String? defaultAgentProvider,
    String? locale,
    List<Map<String, String>>? builtinSlashCommands,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontSize: fontSize ?? this.fontSize,
      terminalCursorBlink: terminalCursorBlink ?? this.terminalCursorBlink,
      defaultAgentProvider: defaultAgentProvider ?? this.defaultAgentProvider,
      locale: locale ?? this.locale,
      builtinSlashCommands: builtinSlashCommands ?? this.builtinSlashCommands,
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
    final builtinJson = prefs.getString('builtin_slash_commands');
    final List<Map<String, String>> builtinCmds;
    if (builtinJson != null) {
      final decoded = jsonDecode(builtinJson) as List<dynamic>;
      builtinCmds = decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } else {
      builtinCmds = List<Map<String, String>>.from(
        _kDefaultBuiltinCommands.map((m) => Map<String, String>.from(m)),
      );
    }
    state = AppSettings(
      themeMode: _parseThemeMode(prefs.getString('theme_mode') ?? 'system'),
      fontSize: prefs.getDouble('terminal_font_size') ?? 14.0,
      terminalCursorBlink: prefs.getBool('terminal_cursor_blink') ?? true,
      defaultAgentProvider: prefs.getString('default_agent_provider') ?? 'claude-code',
      locale: locale,
      builtinSlashCommands: builtinCmds,
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

  Future<void> addBuiltinSlashCommand(String name, String description) async {
    final updated = [
      ...state.builtinSlashCommands,
      {'name': name, 'description': description},
    ];
    state = state.copyWith(builtinSlashCommands: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('builtin_slash_commands', jsonEncode(updated));
  }

  Future<void> removeBuiltinSlashCommand(int index) async {
    final updated = List<Map<String, String>>.from(state.builtinSlashCommands)
      ..removeAt(index);
    state = state.copyWith(builtinSlashCommands: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('builtin_slash_commands', jsonEncode(updated));
  }

  Future<void> setBuiltinSlashCommands(List<Map<String, String>> commands) async {
    state = state.copyWith(builtinSlashCommands: commands);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('builtin_slash_commands', jsonEncode(commands));
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
