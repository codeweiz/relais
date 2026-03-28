import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../l10n/strings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _showAddCommandDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.addCommand),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: S.commandName,
                hintText: 'e.g. help',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: S.commandDescription,
                hintText: 'e.g. Show help',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.addCommand),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final name = nameCtrl.text.trim();
      final desc = descCtrl.text.trim();
      if (name.isNotEmpty) {
        await ref.read(settingsProvider.notifier).addBuiltinSlashCommand(name, desc);
      }
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                      Text('${settings.fontSize.round()}px', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  Slider(
                    value: settings.fontSize,
                    min: 10,
                    max: 24,
                    divisions: 14,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setFontSize(v),
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

          // ── Built-in Slash Commands ────────────────────
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(S.builtinSlashCommands, style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: _showAddCommandDialog,
                icon: const Icon(Icons.add, size: 18),
                label: Text(S.addCommand),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card.filled(
            child: settings.builtinSlashCommands.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      S.noCommandsAvailable,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: settings.builtinSlashCommands.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final cmd = settings.builtinSlashCommands[index];
                      return Dismissible(
                        key: ValueKey('builtin_cmd_${index}_${cmd['name']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (_) {
                          ref
                              .read(settingsProvider.notifier)
                              .removeBuiltinSlashCommand(index);
                        },
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          title: Text(
                            '/${cmd['name']}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          subtitle: cmd['description']!.isNotEmpty
                              ? Text(cmd['description']!)
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: Theme.of(context).colorScheme.error,
                            onPressed: () {
                              ref
                                  .read(settingsProvider.notifier)
                                  .removeBuiltinSlashCommand(index);
                            },
                          ),
                        ),
                      );
                    },
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
