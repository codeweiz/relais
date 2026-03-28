import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import '../models/agent_status.dart';
import '../widgets/office_painter.dart' show providerColor;

bool get _isMobilePlatform {
  final p = defaultTargetPlatform;
  return p == TargetPlatform.iOS || p == TargetPlatform.android;
}

class AgentPickerController {
  OverlayEntry? _overlayEntry;

  void show({
    required BuildContext context,
    required LayerLink layerLink,
    required List<AgentStatusInfo> agents,
    required ValueChanged<AgentStatusInfo> onSelect,
    required VoidCallback onDismiss,
  }) {
    if (_isMobilePlatform) {
      _showBottomSheet(context, agents, onSelect, onDismiss);
      return;
    }
    _removeOverlay();
    _overlayEntry = OverlayEntry(
      builder: (_) => _DesktopAgentPicker(
        layerLink: layerLink,
        agents: agents,
        onSelect: (agent) {
          _removeOverlay();
          onSelect(agent);
        },
        onDismiss: () {
          _removeOverlay();
          onDismiss();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  bool get isVisible => _overlayEntry != null;
  void dismiss() => _removeOverlay();

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showBottomSheet(
    BuildContext context,
    List<AgentStatusInfo> agents,
    ValueChanged<AgentStatusInfo> onSelect,
    VoidCallback onDismiss,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ...agents.map((agent) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: providerColor(agent.provider),
                    radius: 16,
                    child: Text(
                      agent.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  title: Text(agent.name),
                  subtitle: Text('${agent.provider} · ${agent.status}'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onSelect(agent);
                  },
                )),
          ],
        ),
      ),
    ).whenComplete(onDismiss);
  }
}

class _DesktopAgentPicker extends StatelessWidget {
  final LayerLink layerLink;
  final List<AgentStatusInfo> agents;
  final ValueChanged<AgentStatusInfo> onSelect;
  final VoidCallback onDismiss;

  const _DesktopAgentPicker({
    required this.layerLink,
    required this.agents,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 300),
          child: agents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No agents available'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: agents.length,
                  itemBuilder: (context, index) {
                    final agent = agents[index];
                    return InkWell(
                      onTap: () => onSelect(agent),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: providerColor(agent.provider),
                              radius: 14,
                              child: Text(
                                agent.name[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    agent.name,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    '${agent.provider} · ${agent.status}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline),
                                  ),
                                ],
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
