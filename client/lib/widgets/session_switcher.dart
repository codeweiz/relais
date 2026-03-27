import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/session.dart';
import '../providers/session_provider.dart';

class SessionSwitcher extends ConsumerWidget {
  final String currentSessionId;
  final SessionKind filterKind;

  const SessionSwitcher({
    super.key,
    required this.currentSessionId,
    required this.filterKind,
  });

  String _formatTime(String isoTime) {
    try {
      final dt = DateTime.parse(isoTime);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionProvider);

    return sessions.when(
      data: (list) {
        final filtered = list.where((s) => s.kind == filterKind).toList();
        if (filtered.length <= 1) {
          // Only one session, just show the name
          final current = filtered.firstWhere(
            (s) => s.id == currentSessionId,
            orElse: () =>
                filtered.isNotEmpty ? filtered.first : list.first,
          );
          return Text(current.name, style: const TextStyle(fontSize: 14));
        }

        return PopupMenuButton<String>(
          tooltip: 'Switch session',
          offset: const Offset(0, 40),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filtered
                    .firstWhere((s) => s.id == currentSessionId,
                        orElse: () => filtered.first)
                    .name,
                style: const TextStyle(fontSize: 14),
              ),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          itemBuilder: (context) => filtered.map((s) {
            final isCurrent = s.id == currentSessionId;
            return PopupMenuItem<String>(
              value: s.id,
              child: Row(
                children: [
                  Icon(
                    isCurrent ? Icons.check : (s.isAgent ? Icons.smart_toy : Icons.terminal),
                    size: 16,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(s.name, style: const TextStyle(fontSize: 14)),
                        Text(
                          '${s.id.substring(0, 8)} · ${_formatTime(s.createdAt)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onSelected: (id) {
            if (id != currentSessionId) {
              final path = filterKind == SessionKind.agent
                  ? '/agent/$id'
                  : '/terminal/$id';
              context.go(path);
            }
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
