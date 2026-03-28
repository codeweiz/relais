import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/task.dart';
import '../l10n/strings.dart';

class TaskQueuePanel extends StatefulWidget {
  final List<TaskInfo> tasks;
  final VoidCallback onNewTask;

  const TaskQueuePanel({
    super.key,
    required this.tasks,
    required this.onNewTask,
  });

  @override
  State<TaskQueuePanel> createState() => _TaskQueuePanelState();
}

class _TaskQueuePanelState extends State<TaskQueuePanel> {
  bool _expanded = false;

  List<TaskInfo> get _activeTasks =>
      widget.tasks.where((t) => !_isTerminal(t.status)).toList();

  bool _isTerminal(String status) =>
      status == 'completed' || status == 'failed' || status == 'cancelled';

  Color _priorityColor(String priority) {
    switch (priority.toUpperCase()) {
      case 'P0':
        return Colors.red;
      case 'P1':
        return Colors.orange;
      case 'P2':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _statusIcon(String status) {
    switch (status) {
      case 'running':
        return const Text('\u{1F7E2}', style: TextStyle(fontSize: 12));
      case 'queued':
        return const Text('\u{1F7E1}', style: TextStyle(fontSize: 12));
      case 'needs_review':
        return const Text('\u{1F535}', style: TextStyle(fontSize: 12));
      default:
        return const Text('\u26AA', style: TextStyle(fontSize: 12));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _activeTasks;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header bar
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    '\u{1F4CB} ${S.taskQueue} (${active.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: widget.onNewTask,
                    tooltip: S.newTask,
                    visualDensity: VisualDensity.compact,
                  ),
                  Icon(
                    _expanded ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          // Expanded task list
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: active.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(S.noAgentsRunning,
                          style: theme.textTheme.bodySmall),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: active.length,
                      itemBuilder: (context, index) {
                        final task = active[index];
                        return InkWell(
                          onTap: task.isRunning && task.sessionId != null
                              ? () =>
                                  context.push('/agent/${task.sessionId}')
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Row(
                              children: [
                                // Priority chip
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _priorityColor(task.priority)
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.priority.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _priorityColor(task.priority),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Title
                                Expanded(
                                  child: Text(
                                    task.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Target agent
                                Text(
                                  task.isUnassigned
                                      ? S.unassigned
                                      : '\u2192 ${task.targetAgent}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: task.isUnassigned
                                        ? theme.colorScheme.outline
                                        : theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Status
                                _statusIcon(task.status),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
