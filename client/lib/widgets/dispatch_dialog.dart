import 'package:flutter/material.dart';
import '../models/agent_status.dart';
import '../widgets/office_painter.dart' show providerColor;
import '../l10n/strings.dart';

class DispatchDialog extends StatefulWidget {
  final List<AgentStatusInfo> agents;
  final void Function(
      String targetAgent, String title, String prompt, String priority) onDispatch;

  const DispatchDialog({
    super.key,
    required this.agents,
    required this.onDispatch,
  });

  @override
  State<DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<DispatchDialog> {
  AgentStatusInfo? _selectedAgent;
  final _titleController = TextEditingController();
  final _promptController = TextEditingController();
  String _priority = 'p1';

  @override
  void dispose() {
    _titleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(S.newTask),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Agent selection
            Text(S.selectAgent, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: widget.agents.map((agent) {
                final selected = _selectedAgent?.sessionId == agent.sessionId;
                return ChoiceChip(
                  avatar: CircleAvatar(
                    backgroundColor: providerColor(agent.provider),
                    radius: 10,
                    child: Text(
                      agent.name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 9),
                    ),
                  ),
                  label: Text(agent.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedAgent = agent),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Title
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: S.taskTitle,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            // Description
            TextField(
              controller: _promptController,
              decoration: InputDecoration(
                labelText: S.taskDescription,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            // Priority
            Row(
              children: [
                Text(S.priority, style: theme.textTheme.labelMedium),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'p0', label: Text('P0')),
                    ButtonSegment(value: 'p1', label: Text('P1')),
                    ButtonSegment(value: 'p2', label: Text('P2')),
                  ],
                  selected: {_priority},
                  onSelectionChanged: (v) =>
                      setState(() => _priority = v.first),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed:
              _selectedAgent == null || _titleController.text.trim().isEmpty
                  ? null
                  : () {
                      widget.onDispatch(
                        _selectedAgent!.name,
                        _titleController.text.trim(),
                        _promptController.text.trim(),
                        _priority,
                      );
                      Navigator.of(context).pop();
                    },
          child: Text(S.dispatch),
        ),
      ],
    );
  }
}
