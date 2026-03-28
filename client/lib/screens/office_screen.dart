import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/agent_status_provider.dart';
import '../widgets/office_painter.dart';
import '../l10n/strings.dart';

class OfficeScreen extends ConsumerStatefulWidget {
  const OfficeScreen({super.key});

  @override
  ConsumerState<OfficeScreen> createState() => _OfficeScreenState();
}

class _OfficeScreenState extends ConsumerState<OfficeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agents = ref.watch(agentStatusProvider);
    final agentList = agents.values.toList();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/home')),
        title: Text(S.office),
      ),
      body: agentList.isEmpty
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
                                  agent: agent,
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
            ),
    );
  }
}
