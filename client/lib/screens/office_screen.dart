import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/agent_status.dart';
import '../providers/agent_status_provider.dart';
import '../providers/task_provider.dart';
import '../widgets/dispatch_dialog.dart';
import '../widgets/office_painter.dart';
import '../widgets/task_queue_panel.dart';
import '../l10n/strings.dart';

class OfficeScreen extends ConsumerStatefulWidget {
  const OfficeScreen({super.key});

  @override
  ConsumerState<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends ConsumerState<OfficeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  Timer? _blinkTimer;
  bool _blinking = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _blinkTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _blinking = true);
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _blinking = false);
      });
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _showDispatchDialog(BuildContext context, WidgetRef ref) {
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

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentStatusProvider);
    final agentList = agents.values.toList();
    final tasks = ref.watch(taskProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/home')),
        title: Text(S.office),
      ),
      body: Column(
        children: [
          Expanded(
            child: agentList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.groups_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(S.noAgentsRunning,
                            style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  )
                : AnimatedBuilder(
                    animation: _animController,
                    builder: (context, _) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final theme = Theme.of(context);
                          final isDark = theme.brightness == Brightness.dark;
                          final bgStart = isDark
                              ? const Color(0xFF0A0E1A)
                              : const Color(0xFFF0F2F5);
                          final bgEnd = isDark
                              ? const Color(0xFF151B2E)
                              : const Color(0xFFE8EBF0);
                          final gridLineColor = isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.04);
                          final agentLabelColor =
                              isDark ? Colors.white : Colors.black87;

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
                                  Size(constraints.maxWidth,
                                      constraints.maxHeight),
                                );
                                const slotSize = Size(160, 200);

                                // Enhance bubble with linked running task title
                                final linkedTask = tasks
                                    .where((t) =>
                                        t.isRunning &&
                                        t.sessionId == agent.sessionId)
                                    .firstOrNull;
                                final displayAgent = linkedTask != null
                                    ? AgentStatusInfo(
                                        sessionId: agent.sessionId,
                                        name: agent.name,
                                        provider: agent.provider,
                                        status: agent.status,
                                        activity:
                                            '\u{1F4CB} ${linkedTask.name}',
                                        costUsd: agent.costUsd,
                                      )
                                    : agent;

                                return Positioned(
                                  left: pos.dx - slotSize.width / 2,
                                  top: pos.dy - slotSize.height / 2,
                                  width: slotSize.width,
                                  height: slotSize.height,
                                  child: GestureDetector(
                                    onTap: () => context
                                        .push('/agent/${agent.sessionId}'),
                                    child: CustomPaint(
                                      painter: AgentPainter(
                                        agent: displayAgent,
                                        animationValue: _animController.value,
                                        isBlinking: _blinking,
                                        isBubbleExpanded: false,
                                        labelColor: agentLabelColor,
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
                  ),
          ),
          TaskQueuePanel(
            tasks: tasks,
            onNewTask: () => _showDispatchDialog(context, ref),
          ),
        ],
      ),
    );
  }
}
