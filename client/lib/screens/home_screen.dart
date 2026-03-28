import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/agent_status.dart';
import '../models/session.dart';
import '../models/slash_command.dart';
import '../models/task.dart';
import '../services/api_client.dart';
import '../providers/agent_provider.dart';
import '../providers/agent_status_provider.dart';
import '../providers/server_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/dispatch_dialog.dart';
import '../widgets/office_painter.dart';
import '../widgets/session_card.dart';
import '../widgets/slash_command_menu.dart';
import '../l10n/strings.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  // Status glow / ring pulsing — continuous 2-second repeat.
  late final AnimationController _statusAnimController;

  // Blink timer.
  Timer? _blinkTimer;
  bool _blinking = false;

  // Per-agent bubble expand state.
  final Set<String> _expandedBubbles = {};

  // Bottom panel state.
  bool _panelExpanded = false;
  int _selectedTab = 0; // 0 = Sessions, 1 = Tasks

  @override
  void initState() {
    super.initState();

    _statusAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Trigger a 150 ms blink every ~3 seconds.
    _blinkTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _blinking = true);
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _blinking = false);
      });
    });

    Future.microtask(() => ref.read(sessionProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _statusAnimController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  // ── Create helpers ──────────────────────────────────────────────────────────

  Future<void> _createSession(SessionKind kind, {String? name}) async {
    final displayName = (name != null && name.isNotEmpty)
        ? name
        : (kind == SessionKind.agent ? 'Agent' : 'Terminal');
    final notifier = ref.read(sessionProvider.notifier);

    String? id;
    if (kind == SessionKind.agent) {
      id = await notifier.createAgent(displayName);
    } else {
      id = await notifier.createTerminal(displayName);
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
                _showNameDialog(SessionKind.terminal);
              },
            ),
            ListTile(
              leading: const Icon(Icons.smart_toy),
              title: Text(S.newAgent),
              onTap: () {
                Navigator.pop(context);
                _showAgentCreateDialog();
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

  void _showNameDialog(SessionKind kind) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.newTerminal),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: S.name,
            hintText: 'e.g. Build Server',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(S.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _createSession(kind, name: controller.text.trim());
            },
            child: Text(S.create),
          ),
        ],
      ),
    );
  }

  void _showAgentCreateDialog() {
    showDialog(
      context: context,
      builder: (_) => _AgentCreateDialog(
        onCreated: (name, provider) async {
          final server = ref.read(serverProvider).server;
          if (server == null) return;
          final api = ApiClient(baseUrl: server.url, token: server.token);
          final resp = await api.createSession(
            name: name,
            type: 'agent',
            provider: provider,
          );
          final id = resp['id'] as String?;
          if (id != null && mounted) {
            ref.read(sessionProvider.notifier).refresh();
            context.push('/agent/$id');
          }
        },
      ),
    );
  }

  void _showQuickMessage(AgentStatusInfo agent) {
    final server = ref.read(serverProvider).server;
    if (server == null) return;
    final agentSession = ref.read(agentSessionManagerProvider).getOrCreate(
      sessionId: agent.sessionId,
      baseUrl: server.url,
      token: server.token,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _QuickMessageSheet(
        agentName: agent.name,
        sessionId: agent.sessionId,
        agentSession: agentSession,
        onSent: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  // ── Bubble expand/collapse ────────────────────────────────────────────────

  void _toggleBubble(String sessionId) {
    setState(() {
      if (_expandedBubbles.contains(sessionId)) {
        _expandedBubbles.remove(sessionId);
      } else {
        _expandedBubbles.add(sessionId);
      }
    });
  }

  // ── Workspace canvas ─────────────────────────────────────────────────────

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

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme-aware background colors
    final bgStart = isDark
        ? const Color(0xFF0A0E1A)
        : const Color(0xFFF0F2F5);
    final bgEnd = isDark
        ? const Color(0xFF151B2E)
        : const Color(0xFFE8EBF0);
    final gridLineColor = isDark
        ? Colors.white.withValues(alpha: 0.03)
        : Colors.black.withValues(alpha: 0.04);
    final agentLabelColor = isDark ? Colors.white : Colors.black87;

    return AnimatedBuilder(
      animation: _statusAnimController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: OfficePainter(
                backgroundColor: bgStart,
                backgroundColorEnd: bgEnd,
                gridColor: gridLineColor,
              ),
              child: Stack(
                children: List.generate(agentList.length, (index) {
                  final agent = agentList[index];
                  final pos = slotPosition(
                    index,
                    agentList.length,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  const slotSize = Size(160, 200);

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

                  final isExpanded = _expandedBubbles.contains(agent.sessionId);

                  return Positioned(
                    left: pos.dx - slotSize.width / 2,
                    top: pos.dy - slotSize.height / 2,
                    width: slotSize.width,
                    height: slotSize.height,
                    child: Stack(
                      children: [
                        // Main agent area — tap = navigate to chat, long press = quick message
                        GestureDetector(
                          onTap: () =>
                              context.push('/agent/${agent.sessionId}'),
                          onLongPress: () => _showQuickMessage(agent),
                          child: CustomPaint(
                            painter: AgentPainter(
                              agent: displayAgent,
                              animationValue: _statusAnimController.value,
                              isBlinking: _blinking,
                              isBubbleExpanded: isExpanded,
                              labelColor: agentLabelColor,
                            ),
                            size: slotSize,
                          ),
                        ),
                        // Bubble tap target (top portion of slot) — toggles expand
                        if (agent.activity.isNotEmpty)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: slotSize.height * 0.38,
                            child: GestureDetector(
                              onTap: () => _toggleBubble(agent.sessionId),
                              behavior: HitTestBehavior.translucent,
                            ),
                          ),
                      ],
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

  // ── Bottom panel ─────────────────────────────────────────────────────────

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

    final expandedHeight =
        (MediaQuery.of(context).size.height * 0.35).clamp(140.0, 320.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      height: _panelExpanded ? expandedHeight : 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _panelExpanded = !_panelExpanded),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: 8),
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
    final agents = ref.read(agentStatusProvider);
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
        return _TaskRow(
          task: task,
          agents: agents,
          onCancel: () =>
              ref.read(taskProvider.notifier).cancelTask(task.id),
        );
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
          Expanded(
            child: _buildWorkspace(context, agentList, tasks),
          ),
          Container(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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

// ── Quick message bottom sheet ────────────────────────────────────────────────

class _QuickMessageSheet extends ConsumerStatefulWidget {
  final String agentName;
  final String sessionId;
  final AgentSession agentSession;
  final VoidCallback onSent;

  const _QuickMessageSheet({
    required this.agentName,
    required this.sessionId,
    required this.agentSession,
    required this.onSent,
  });

  @override
  ConsumerState<_QuickMessageSheet> createState() => _QuickMessageSheetState();
}

class _QuickMessageSheetState extends ConsumerState<_QuickMessageSheet> {
  final _inputController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _speech = stt.SpeechToText();
  bool _isListening = false;

  // Inline slash-command and agent picker state (avoids Overlay context issues
  // inside ModalBottomSheet).
  List<SlashCommand> _filteredCommands = [];
  List<AgentStatusInfo> _filteredAgents = [];

  @override
  void dispose() {
    _speech.stop();
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onInputChanged(String text) {
    // Slash command detection
    if (text.startsWith('/') && !text.contains(' ')) {
      final filter = text.substring(1);
      final dynamic = widget.agentSession.availableCommands ?? [];
      final builtins = ref.read(settingsProvider).builtinSlashCommands
          .map((m) => SlashCommand(name: m['name']!, description: m['description']!))
          .toList();
      final dynamicNames = dynamic.map((c) => c.name).toSet();
      final merged = [...dynamic, ...builtins.where((c) => !dynamicNames.contains(c.name))];
      setState(() {
        _filteredCommands = filterCommands(merged, filter);
        _filteredAgents = [];
      });
    } else if (text.startsWith('@') && !text.contains(' ')) {
      // @ agent picker detection
      final agents = ref.read(agentStatusProvider);
      setState(() {
        _filteredAgents = agents.values
            .where((a) => a.sessionId != widget.sessionId)
            .toList();
        _filteredCommands = [];
      });
    } else {
      if (_filteredCommands.isNotEmpty || _filteredAgents.isNotEmpty) {
        setState(() {
          _filteredCommands = [];
          _filteredAgents = [];
        });
      }
    }
  }

  void _onCommandSelected(SlashCommand cmd) {
    _inputController.text = '/${cmd.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    setState(() => _filteredCommands = []);
    _inputFocusNode.requestFocus();
  }

  void _onAgentSelected(AgentStatusInfo agent) {
    _inputController.text = '@${agent.name} ';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    setState(() => _filteredAgents = []);
    _inputFocusNode.requestFocus();
  }

  Future<void> _dispatchTask(String text) async {
    final spaceIndex = text.indexOf(' ');
    if (spaceIndex < 0) return;
    final targetName = text.substring(1, spaceIndex);
    final description = text.substring(spaceIndex + 1).trim();
    if (description.isEmpty) return;

    final agents = ref.read(agentStatusProvider);
    final targetExists = agents.values.any((a) => a.name == targetName);
    if (!targetExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.agentNotFound)),
        );
      }
      return;
    }

    await ref.read(taskProvider.notifier).createTask(
      title: description.length > 50
          ? '${description.substring(0, 50)}...'
          : description,
      prompt: description,
      targetAgent: targetName,
      sourceSessionId: widget.sessionId,
    );
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
            sourceSessionId: widget.sessionId,
          );
        },
      ),
    );
  }

  void _send() {
    setState(() { _filteredCommands = []; _filteredAgents = []; });
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    if (_isListening) {
      _speech.cancel();
      _isListening = false;
    }

    // @ dispatch — create task instead of sending to current agent
    if (text.startsWith('@') && text.contains(' ')) {
      _dispatchTask(text);
      _inputController.value = TextEditingValue.empty;
      widget.onSent();
      return;
    }

    widget.agentSession.sendMessage(text);
    _inputController.value = TextEditingValue.empty;
    widget.onSent();
  }

  Future<void> _toggleVoice() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (_) => setState(() => _isListening = false),
    );
    if (!available) return;
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'zh-CN',
      onResult: (result) {
        if (!_isListening) return;
        _inputController.text = result.recognizedWords;
        _inputController.selection = TextSelection.collapsed(
          offset: _inputController.text.length,
        );
        if (result.finalResult) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              _t('发送给 ${widget.agentName}', 'Send to ${widget.agentName}'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          // Inline slash command list (avoids Overlay context issues in ModalBottomSheet)
          if (_filteredCommands.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _filteredCommands.length,
                itemBuilder: (context, index) {
                  final cmd = _filteredCommands[index];
                  return InkWell(
                    onTap: () => _onCommandSelected(cmd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          // Inline agent picker
          if (_filteredAgents.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _filteredAgents.length,
                itemBuilder: (context, index) {
                  final agent = _filteredAgents[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      backgroundColor: providerColor(agent.provider),
                      radius: 14,
                      child: Text(
                        agent.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                    title: Text(agent.name),
                    subtitle: Text('${agent.provider} · ${agent.status}'),
                    onTap: () => _onAgentSelected(agent),
                  );
                },
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    onPressed: _showDispatchDialog,
                    icon: const Text('@',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        )),
                    tooltip: S.dispatchTo,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _inputFocusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: S.sendMessage,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        isDense: true,
                      ),
                      onChanged: _onInputChanged,
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? theme.colorScheme.error
                          : null,
                    ),
                    tooltip: _isListening ? '停止' : '语音输入',
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _t(String zh, String en) => S.locale == 'zh' ? zh : en;
}

class _TaskRow extends StatelessWidget {
  final TaskInfo task;
  final Map<String, AgentStatusInfo> agents;
  final VoidCallback onCancel;

  const _TaskRow({
    required this.task,
    required this.agents,
    required this.onCancel,
  });

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

  void _navigateToAgent(BuildContext context) {
    // Try to find the target agent's session by name
    final targetAgent = agents.values
        .where((a) => a.name == task.targetAgent)
        .firstOrNull;
    if (targetAgent != null) {
      context.push('/agent/${targetAgent.sessionId}');
    } else if (task.sessionId != null) {
      context.push('/agent/${task.sessionId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: task.isRunning && task.sessionId != null
          ? () => _navigateToAgent(context)
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
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.error.withValues(alpha: 0.7),
                ),
                tooltip: S.cancel,
                onPressed: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Agent create dialog ──────────────────────────────────────────────────────

class _AgentCreateDialog extends StatefulWidget {
  final Future<void> Function(String name, String provider) onCreated;
  const _AgentCreateDialog({required this.onCreated});
  @override
  State<_AgentCreateDialog> createState() => _AgentCreateDialogState();
}

class _AgentCreateDialogState extends State<_AgentCreateDialog> {
  final _nameController = TextEditingController();
  String _provider = 'claude-code';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(S.newAgent),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: S.name,
              hintText: 'e.g. Frontend Dev',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          Text(S.selectAgent, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Claude Code'),
                selected: _provider == 'claude-code',
                onSelected: (_) => setState(() => _provider = 'claude-code'),
              ),
              ChoiceChip(
                label: const Text('Codex CLI'),
                selected: _provider == 'codex',
                onSelected: (_) => setState(() => _provider = 'codex'),
              ),
              ChoiceChip(
                label: const Text('Gemini CLI'),
                selected: _provider == 'gemini',
                onSelected: (_) => setState(() => _provider = 'gemini'),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(S.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim().isEmpty
                ? _provider == 'claude-code'
                    ? 'Claude Code'
                    : _provider
                : _nameController.text.trim();
            Navigator.pop(context);
            widget.onCreated(name, _provider);
          },
          child: Text(S.create),
        ),
      ],
    );
  }
}
