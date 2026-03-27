import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/server_provider.dart';
import '../providers/session_provider.dart';
import '../models/session.dart';
import '../widgets/session_card.dart';
import '../l10n/strings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(sessionProvider.notifier).refresh());
  }

  Future<void> _createSession(SessionKind kind) async {
    final name = kind == SessionKind.agent ? 'Agent' : 'Terminal';
    final notifier = ref.read(sessionProvider.notifier);

    String? id;
    if (kind == SessionKind.agent) {
      id = await notifier.createAgent(name);
    } else {
      id = await notifier.createTerminal(name);
    }

    if (id != null && mounted) {
      final path =
          kind == SessionKind.agent ? '/agent/$id' : '/terminal/$id';
      context.push(path);
    }
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.terminal),
              title: Text(S.newTerminal),
              onTap: () {
                Navigator.pop(context);
                _createSession(SessionKind.terminal);
              },
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy),
              title: Text(S.newAgent),
              onTap: () {
                Navigator.pop(context);
                _createSession(SessionKind.agent);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverProvider);
    final sessions = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(serverState.server?.name ?? 'Relais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(sessionProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(serverProvider.notifier).disconnect();
              context.go('/');
            },
          ),
        ],
      ),
      body: sessions.when(
        data: (list) => list.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(S.noSessions,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: _showCreateDialog,
                      icon: const Icon(Icons.add),
                      label: Text(S.createSession),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(sessionProvider.notifier).refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final session = list[index];
                    return SessionCard(
                      session: session,
                      onTap: () {
                        final path = session.isAgent
                            ? '/agent/${session.id}'
                            : '/terminal/${session.id}';
                        context.push(path);
                      },
                      onDelete: () => ref
                          .read(sessionProvider.notifier)
                          .deleteSession(session.id),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
