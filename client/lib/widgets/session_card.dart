import 'package:flutter/material.dart';
import '../models/session.dart';

class SessionCard extends StatelessWidget {
  final Session session;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const SessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card.filled(
      child: ListTile(
        leading: Icon(
          session.isAgent ? Icons.smart_toy : Icons.terminal,
          color: colorScheme.primary,
        ),
        title: Text(session.name),
        subtitle: Text(session.id),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: session.status),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final SessionStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      SessionStatus.running || SessionStatus.working => (Colors.green, 'Running'),
      SessionStatus.ready || SessionStatus.idle => (Colors.blue, 'Ready'),
      SessionStatus.crashed => (Colors.red, 'Crashed'),
      SessionStatus.exited => (Colors.grey, 'Exited'),
      SessionStatus.initializing => (Colors.orange, 'Starting'),
      _ => (Colors.grey, status.name),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
