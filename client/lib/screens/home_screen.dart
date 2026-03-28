import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/agent_status.dart';
import '../models/session.dart';
import '../models/task.dart';
import '../providers/agent_status_provider.dart';
import '../providers/server_provider.dart';
import '../providers/session_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/dispatch_dialog.dart';
import '../widgets/office_painter.dart';
import '../widgets/session_card.dart';
import '../l10n/strings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  // Bottom panel state
  bool _panelExpanded = false;
  int _selectedTab = 0; // 0 = Sessions, 1 = Tasks

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    Future.microtask(() => ref.read(sessionProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // ── Create helpers ──────────────────────────────────────────────────────────

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

  void _showDispatchDialog() {
    final agents = ref.read(agentStatusProvider);
    showDialog(
      context: context,
      builder: (_) => DispatchDialog(
        agents: agents.values.toList(),
        onDispatch: (targetAgent, title, prompt, priority) {
          ref.read(taskProvider.notifier).createTask(
                title: title,
                prompt: prompt.isEmpty ? title : prompt,
                priority: priority,
                targetAgent: targetAgent,
              );
        },
      ),
    );
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
            ListTile(
              leading: const Icon(Icons.task_alt),
              title: Text(S.newTask),
              onTap: () {
                Navigator.pop(context);
                _showDispatchDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Workspace canvas ────────────────────────────────────────────────────────

  Widget _buildWorkspace(
    BuildContext context,
    List<AgentStatusInfo> agentList,
    List<TaskInfo> tasks,
  ) {
    if (agentList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.groups_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(S.noAgentsRunning,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add),
              label: Text(S.createSession),
            ),
          ],
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: OfficePainter(),
              child: Stack(
                children: List.generate(agentList.length, (index) {
                  final agent = agentList[index];
                  final pos = slotPosition(
                    index,
                    agentList.length,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  const slotSize = Size(140, 160);

                  final linkedTask = tasks
                      .where((t) =>
                          t.isRunning && t.sessionId == agent.sessionId)
                      .firstOrNull;
                  final displayAgent = linkedTask != null
                      ? AgentStatusInfo(
                          sessionId: agent.sessionId,
                          name: agent.name,
                          provider: agent.provider,
                          status: agent.status,
                          activity: '\u{1F4CB} ${linkedTask.name}',
                          costUsd: agent.costUsd,
                        )
                      : agent;

                  return Positioned(
                    left: pos.dx - slotSize.width / 2,
                    top: pos.dy - slotSize.height / 2,
                    width: slotSize.width,
                    height: slotSize.height,
                    child: GestureDetector(
                      onTap: () =>
                          context.push('/agent/${agent.sessionId}'),
                      child: CustomPaint(
                        painter: AgentPainter(
                          agent: displayAgent,
                          animationValue: _animController.value,
                        ),
                        size: slotSize,
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }

  // ── Bottom panel ────────────────────────────────────────────────────────────

  Widget _buildBottomPanel(
    BuildContext context,
    List<Session> sessions,
    List<TaskInfo> tasks,
  ) {
    final theme = Theme.of(context);
    final activeTasks = tasks
        .where((t) =>
            t.status != 'completed' &&
            t.status != 'failed' &&
            t.status != 'cancelled')
        .toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      // Collapsed: ~56dp (tab bar only). Expanded: up to 40% of screen height.
      constraints: BoxConstraints(
        maxHeight: _panelExpanded
            ? MediaQuery.of(context).size.height * 0.40
            : 56,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab bar / header row
          InkWell(
            onTap: () => setState(() => _panelExpanded = !_panelExpanded),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  // Sessions tab
                  _PanelTab(
                    label: S.sessions,
                    count: sessions.length,
                    selected: _selectedTab == 0,
                    onTap: () => setState(() {
                      _selectedTab = 0;
                      _panelExpanded = true;
                    }),
                  ),
                  const SizedBox(width: 4),
                  // Tasks tab
                  _PanelTab(
                    label: S.tasks,
                    count: activeTasks.length,
                    selected: _selectedTab == 1,
                    onTap: () => setState(() {
                      _selectedTab = 1;
                      _panelExpanded = true;
                    }),
                  ),
                  const Spacer(),
                  Icon(
                    _panelExpanded ? Icons.expand_more : Icons.expand_less,
                    size: 20,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          // Panel content (only visible when expanded)
          if (_panelExpanded)
            Flexible(
              child: _selectedTab == 0
                  ? _buildSessionsList(context, sessions)
                  : _buildTasksList(context, activeTasks),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionsList(BuildContext context, List<Session> sessions) {
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(S.noSessions,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  )),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        itemCount: sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
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
    );
  }

  Widget _buildTasksList(BuildContext context, List<TaskInfo> activeTasks) {
    final theme = Theme.of(context);
    if (activeTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(S.noAgentsRunning,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              )),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: activeTasks.length,
      itemBuilder: (context, index) {
        final task = activeTasks[index];
        return _TaskRow(task: task);
      },
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(serverProvider);
    final sessionsAsync = ref.watch(sessionProvider);
    final agents = ref.watch(agentStatusProvider);
    final tasks = ref.watch(taskProvider);

    final agentList = agents.values.toList();
    final sessions = sessionsAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(serverState.server?.name ?? 'Relais'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(sessionProvider.notifier).refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: S.settings,
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(serverProvider.notifier).disconnect();
              context.go('/');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Primary workspace canvas
          Expanded(
            child: _buildWorkspace(context, agentList, tasks),
          ),
          // Collapsible bottom panel
          _buildBottomPanel(context, sessions, tasks),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _PanelTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PanelTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(color: color),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final TaskInfo task;
  const _TaskRow({required this.task});

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
    return InkWell(
      onTap: task.isRunning && task.sessionId != null
          ? () => context.push('/agent/${task.sessionId}')
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            Expanded(
              child: Text(
                task.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
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
            _statusIcon(task.status),
          ],
        ),
      ),
    );
  }
}
