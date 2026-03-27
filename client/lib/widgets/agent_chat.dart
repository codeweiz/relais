import 'package:flutter/material.dart';
import '../models/agent_message.dart';
import 'message_bubble.dart';

class AgentChat extends StatelessWidget {
  final List<AgentMessage> messages;
  final ScrollController scrollController;
  final bool waiting;
  final double? fontSize;

  const AgentChat({
    super.key,
    required this.messages,
    required this.scrollController,
    this.waiting = false,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final itemCount = messages.length + (waiting ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return MessageBubble(message: messages[index], fontSize: fontSize);
        }
        // Last item: waiting indicator
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Agent 思考中...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
