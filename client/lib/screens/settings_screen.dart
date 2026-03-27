import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ─────────────────────────────────
          Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setThemeMode(s.first),
                  ),
                ],
              ),
            ),
          ),

          // ── Terminal ───────────────────────────────────
          const SizedBox(height: 24),
          Text('Terminal', style: Theme.of(context).textTheme.titleMedium),
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
                      Text('Font Size', style: Theme.of(context).textTheme.bodyLarge),
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
                    title: const Text('Cursor Blink'),
                    value: settings.terminalCursorBlink,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setTerminalCursorBlink(v),
                  ),
                ],
              ),
            ),
          ),

          // ── Agent ──────────────────────────────────────
          const SizedBox(height: 24),
          Text('Agent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Default Provider', style: Theme.of(context).textTheme.bodyLarge),
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
          Text('Data', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Clear Saved Servers'),
                    subtitle: const Text('Remove all saved server connections'),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear saved servers?'),
                          content: const Text('This will remove all saved server connections.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await ref.read(settingsProvider.notifier).clearSavedServers();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Saved servers cleared')),
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
          Text('About', style: Theme.of(context).textTheme.titleMedium),
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
                    'Remote terminal access and AI agent interaction — from anywhere.',
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
