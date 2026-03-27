import 'package:flutter/material.dart';
import '../models/agent_message.dart';
import 'message_bubble.dart';

class AgentChat extends StatelessWidget {
  final List<AgentMessage> messages;
  final ScrollController scrollController;

  const AgentChat({
    super.key,
    required this.messages,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) => MessageBubble(message: messages[index]),
    );
  }
}
