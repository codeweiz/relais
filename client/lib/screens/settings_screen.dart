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
        await ref
            .read(settingsProvider.notifier)
            .addBuiltinSlashCommand(name, desc);
      }
    }
    nameCtrl.dispose();
    descCtrl.dispose();
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.8,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final cmdCount = settings.builtinSlashCommands.length;

    return Scaffold(
      appBar: AppBar(title: Text(S.settings)),
      body: ListView(
        children: [
          // ── Appearance ─────────────────────────────────────────────────────
          _sectionHeader(context, S.appearance),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(S.theme, style: theme.textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(S.system),
                    icon: const Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(S.light),
                    icon: const Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(S.dark),
                    icon: const Icon(Icons.dark_mode)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) =>
                  ref.read(settingsProvider.notifier).setThemeMode(s.first),
            ),
          ),

          // ── Language ───────────────────────────────────────────────────────
          _sectionHeader(context, S.language),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh', label: Text('简体中文')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {settings.locale},
              onSelectionChanged: (s) =>
                  ref.read(settingsProvider.notifier).setLocale(s.first),
            ),
          ),

          // ── Terminal ───────────────────────────────────────────────────────
          _sectionHeader(context, S.terminal),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(S.fontSize, style: theme.textTheme.bodyMedium),
                Text('${settings.fontSize.round()}px',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    )),
              ],
            ),
          ),
          Slider(
            value: settings.fontSize,
            min: 10,
            max: 24,
            divisions: 14,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setFontSize(v),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: Text(S.cursorBlink),
            value: settings.terminalCursorBlink,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .setTerminalCursorBlink(v),
          ),

          // ── Agent ──────────────────────────────────────────────────────────
          _sectionHeader(context, S.agent),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(S.defaultProvider, style: theme.textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'claude-code', label: Text('Claude')),
                ButtonSegment(value: 'gemini-cli', label: Text('Gemini')),
                ButtonSegment(value: 'opencode', label: Text('OpenCode')),
              ],
              selected: {settings.defaultAgentProvider},
              onSelectionChanged: (s) => ref
                  .read(settingsProvider.notifier)
                  .setDefaultAgentProvider(s.first),
            ),
          ),

          // ── Built-in Slash Commands ────────────────────────────────────────
          const Divider(height: 1),
          ExpansionTile(
            title: Text(S.builtinSlashCommands),
            subtitle: Text(
              cmdCount == 0
                  ? S.noCommandsAvailable
                  : '$cmdCount ${S.tasks.toLowerCase()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            initiallyExpanded: false,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: S.addCommand,
                  onPressed: _showAddCommandDialog,
                  visualDensity: VisualDensity.compact,
                ),
                const Icon(Icons.expand_more),
              ],
            ),
            children: settings.builtinSlashCommands.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        S.noCommandsAvailable,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ),
                  ]
                : List.generate(
                    settings.builtinSlashCommands.length,
                    (index) {
                      final cmd = settings.builtinSlashCommands[index];
                      return Dismissible(
                        key: ValueKey(
                            'builtin_cmd_${index}_${cmd['name']}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: theme.colorScheme.errorContainer,
                          child: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (_) {
                          ref
                              .read(settingsProvider.notifier)
                              .removeBuiltinSlashCommand(index);
                        },
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 0),
                          title: Text(
                            '/${cmd['name']}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          subtitle: cmd['description']!.isNotEmpty
                              ? Text(cmd['description']!,
                                  style:
                                      theme.textTheme.bodySmall)
                              : null,
                        ),
                      );
                    },
                  ),
          ),

          // ── Data ───────────────────────────────────────────────────────────
          _sectionHeader(context, S.dataSection),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(S.clearSavedServers),
            subtitle: Text(S.clearSavedServersDesc,
                style: theme.textTheme.bodySmall),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(S.clearConfirm),
                  content: Text(S.clearConfirmDesc),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(S.cancel)),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(S.clear)),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref
                    .read(settingsProvider.notifier)
                    .clearSavedServers();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(S.cleared)),
                  );
                }
              }
            },
          ),

          // ── About ──────────────────────────────────────────────────────────
          _sectionHeader(context, S.about),
          const Divider(height: 1),
          ListTile(
            leading:
                Icon(Icons.terminal_rounded, color: theme.colorScheme.primary),
            title: const Text('Relais'),
            subtitle: const Text('v1.0.0'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Text(
              S.aboutDesc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
