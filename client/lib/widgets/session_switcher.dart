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
                    isCurrent ? Icons.check : Icons.swap_horiz,
                    size: 16,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(s.name),
                  const Spacer(),
                  Text(s.id.substring(0, 6),
                      style: Theme.of(context).textTheme.bodySmall),
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
