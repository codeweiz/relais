import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../l10n/strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(S.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ─────────────────────────────────
          Text(S.appearance, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.theme, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(value: ThemeMode.system, label: Text(S.system), icon: const Icon(Icons.brightness_auto)),
                      ButtonSegment(value: ThemeMode.light, label: Text(S.light), icon: const Icon(Icons.light_mode)),
                      ButtonSegment(value: ThemeMode.dark, label: Text(S.dark), icon: const Icon(Icons.dark_mode)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setThemeMode(s.first),
                  ),
                ],
              ),
            ),
          ),

          // ── Language ──────────────────────────────────
          const SizedBox(height: 24),
          Text(S.language, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.language, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'zh', label: Text('简体中文')),
                      ButtonSegment(value: 'en', label: Text('English')),
                    ],
                    selected: {settings.locale},
                    onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setLocale(s.first),
                  ),
                ],
              ),
            ),
          ),

          // ── Terminal ───────────────────────────────────
          const SizedBox(height: 24),
          Text(S.terminal, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(S.fontSize, style: Theme.of(context).textTheme.bodyLarge),
                      Text('${settings.terminalFontSize.round()}px', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  Slider(
                    value: settings.terminalFontSize,
                    min: 10,
                    max: 24,
                    divisions: 14,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setTerminalFontSize(v),
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(S.cursorBlink),
                    value: settings.terminalCursorBlink,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setTerminalCursorBlink(v),
                  ),
                ],
              ),
            ),
          ),

          // ── Agent ──────────────────────────────────────
          const SizedBox(height: 24),
          Text(S.agent, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.defaultProvider, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'claude-code', label: Text('Claude')),
                      ButtonSegment(value: 'gemini-cli', label: Text('Gemini')),
                      ButtonSegment(value: 'opencode', label: Text('OpenCode')),
                    ],
                    selected: {settings.defaultAgentProvider},
                    onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setDefaultAgentProvider(s.first),
                  ),
                ],
              ),
            ),
          ),

          // ── Data ───────────────────────────────────────
          const SizedBox(height: 24),
          Text(S.dataSection, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline),
                    title: Text(S.clearSavedServers),
                    subtitle: Text(S.clearSavedServersDesc),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(S.clearConfirm),
                          content: Text(S.clearConfirmDesc),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(S.cancel)),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(S.clear)),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref.read(settingsProvider.notifier).clearSavedServers();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(S.cleared)),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── About ──────────────────────────────────────
          const SizedBox(height: 24),
          Text(S.about, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Relais'),
                    subtitle: const Text('v1.0.0'),
                    trailing: Icon(Icons.terminal_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                  Text(
                    S.aboutDesc,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
