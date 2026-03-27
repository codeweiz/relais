import 'package:flutter/material.dart';
import '../models/session.dart';
import '../l10n/strings.dart';

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

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return S.justNow;
      if (diff.inMinutes < 60) return S.minutesAgo(diff.inMinutes);
      if (diff.inHours < 24) return S.hoursAgo(diff.inHours);
      return S.daysAgo(diff.inDays);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card.filled(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(
            session.isAgent ? Icons.smart_toy : Icons.terminal,
            color: colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(session.name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          '${session.id.substring(0, 8)} · ${_formatTime(session.lastActive)}',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StatusChip(status: session.status),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
                tooltip: S.delete,
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
      SessionStatus.running || SessionStatus.working => (Colors.green, S.running),
      SessionStatus.ready || SessionStatus.idle => (Colors.blue, S.ready),
      SessionStatus.crashed => (Colors.red, S.crashed),
      SessionStatus.exited => (Colors.grey, S.exited),
      SessionStatus.initializing => (Colors.orange, S.starting),
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
