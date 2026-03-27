import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../models/slash_command.dart';
import '../l10n/strings.dart';

/// Filters [commands] by prefix-matching [filter] against command names.
List<SlashCommand> filterCommands(List<SlashCommand> commands, String filter) {
  if (filter.isEmpty) return List.of(commands);
  final lower = filter.toLowerCase();
  final matched =
      commands.where((c) => c.name.toLowerCase().startsWith(lower)).toList();
  matched.sort((a, b) => a.name.compareTo(b.name));
  return matched;
}

bool get _isMobilePlatform {
  final p = defaultTargetPlatform;
  return p == TargetPlatform.iOS || p == TargetPlatform.android;
}

/// Controller for showing/hiding the slash command menu.
class SlashCommandMenuController {
  OverlayEntry? _overlayEntry;
  int _selectedIndex = 0;

  void show({
    required BuildContext context,
    required LayerLink layerLink,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform) {
      _showBottomSheet(
        context: context,
        commands: commands,
        filter: filter,
        onSelect: onSelect,
        onDismiss: onDismiss,
      );
      return;
    }
    _selectedIndex = 0;
    _removeOverlay();
    _rebuildOverlay(context, layerLink, commands, filter, onSelect, onDismiss);
  }

  void updateFilter({
    required BuildContext context,
    required LayerLink layerLink,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform || _overlayEntry == null) return;
    final filtered = filterCommands(commands, filter);
    if (_selectedIndex >= filtered.length) {
      _selectedIndex = filtered.isEmpty ? 0 : filtered.length - 1;
    }
    _removeOverlay();
    _rebuildOverlay(context, layerLink, commands, filter, onSelect, onDismiss);
  }

  bool get isVisible => _overlayEntry != null;

  void dismiss() => _removeOverlay();

  void _rebuildOverlay(
    BuildContext context,
    LayerLink layerLink,
    List<SlashCommand> commands,
    String filter,
    ValueChanged<SlashCommand> onSelect,
    VoidCallback onDismiss,
  ) {
    final filtered = filterCommands(commands, filter);
    _overlayEntry = OverlayEntry(
      builder: (_) => _DesktopOverlay(
        layerLink: layerLink,
        commands: filtered,
        selectedIndex: _selectedIndex,
        onSelect: (cmd) {
          _removeOverlay();
          onSelect(cmd);
        },
        onDismiss: () {
          _removeOverlay();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showBottomSheet({
    required BuildContext context,
    required List<SlashCommand> commands,
    required String filter,
    required ValueChanged<SlashCommand> onSelect,
    required VoidCallback onDismiss,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MobileBottomSheet(
        commands: commands,
        initialFilter: filter,
        onSelect: (cmd) {
          Navigator.of(ctx).pop();
          onSelect(cmd);
        },
      ),
    ).whenComplete(onDismiss);
  }
}

class _DesktopOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final List<SlashCommand> commands;
  final int selectedIndex;
  final ValueChanged<SlashCommand> onSelect;
  final VoidCallback onDismiss;

  const _DesktopOverlay({
    required this.layerLink,
    required this.commands,
    required this.selectedIndex,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = 8 * 40.0;

    return CompositedTransformFollower(
      link: layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.topLeft,
      followerAnchor: Alignment.bottomLeft,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 400),
          child: commands.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(S.noCommandsAvailable,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: commands.length,
                  itemBuilder: (context, index) {
                    final cmd = commands[index];
                    final isSelected = index == selectedIndex;
                    return InkWell(
                      onTap: () => onSelect(cmd),
                      child: Container(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : null,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              '/${cmd.name}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                cmd.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _MobileBottomSheet extends StatefulWidget {
  final List<SlashCommand> commands;
  final String initialFilter;
  final ValueChanged<SlashCommand> onSelect;

  const _MobileBottomSheet({
    required this.commands,
    required this.initialFilter,
    required this.onSelect,
  });

  @override
  State<_MobileBottomSheet> createState() => _MobileBottomSheetState();
}

class _MobileBottomSheetState extends State<_MobileBottomSheet> {
  late final TextEditingController _filterController;
  late List<SlashCommand> _filtered;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController(text: widget.initialFilter);
    _filtered = filterCommands(widget.commands, widget.initialFilter);
    _filterController.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    setState(() {
      _filtered = filterCommands(widget.commands, _filterController.text);
    });
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.5;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: TextField(
              controller: _filterController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: S.slashCommandHint,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(S.noCommandsAvailable,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final cmd = _filtered[index];
                      return ListTile(
                        dense: false,
                        visualDensity: VisualDensity.standard,
                        title: Text(
                          '/${cmd.name}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        subtitle: Text(cmd.description),
                        onTap: () => widget.onSelect(cmd),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
