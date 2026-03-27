import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/agent_message.dart';

class MessageBubble extends StatelessWidget {
  final AgentMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return switch (message.type) {
      AgentMessageType.user => _UserBubble(message: message),
      AgentMessageType.text => _AgentTextBubble(message: message),
      AgentMessageType.thinking => _ThinkingBubble(message: message),
      AgentMessageType.toolUse => _ToolUseBubble(message: message),
      AgentMessageType.toolResult => _ToolResultBubble(message: message),
      AgentMessageType.progress => _ProgressBubble(message: message),
      AgentMessageType.turnComplete => _TurnCompleteBubble(message: message),
      AgentMessageType.error => _ErrorBubble(message: message),
    };
  }
}

class _UserBubble extends StatelessWidget {
  final AgentMessage message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final source = message.source;
    final prefix = source != null && source != 'web' ? '[$source] ' : '';

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('$prefix${message.content}',
            style: TextStyle(color: colorScheme.onPrimaryContainer)),
      ),
    );
  }
}

class _AgentTextBubble extends StatelessWidget {
  final AgentMessage message;
  const _AgentTextBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: MarkdownBody(
          data: message.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  final AgentMessage message;
  const _ThinkingBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.psychology,
              size: 16, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.content,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolUseBubble extends StatefulWidget {
  final AgentMessage message;
  const _ToolUseBubble({required this.message});

  @override
  State<_ToolUseBubble> createState() => _ToolUseBubbleState();
}

class _ToolUseBubbleState extends State<_ToolUseBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final input = widget.message.toolInput;
    final hasInput = input != null && input.isNotEmpty;

    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: hasInput ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.build_circle,
                      size: 20, color: Theme.of(context).colorScheme.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.message.toolName ?? 'Tool',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  if (hasInput)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
              if (_expanded && hasInput) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    input!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolResultBubble extends StatefulWidget {
  final AgentMessage message;
  const _ToolResultBubble({required this.message});

  @override
  State<_ToolResultBubble> createState() => _ToolResultBubbleState();
}

class _ToolResultBubbleState extends State<_ToolResultBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isErr = widget.message.isError == true;
    final content = widget.message.content;
    final isLong = content.length > 200;

    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 2),
      color: isErr
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: isLong ? () => setState(() => _expanded = !_expanded) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isErr ? Icons.error_outline : Icons.check_circle_outline,
                    size: 14,
                    color: isErr
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isErr ? 'Error' : 'Result',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (isLong) ...[
                    const Spacer(),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                _expanded || !isLong ? content : '${content.substring(0, 200)}...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBubble extends StatelessWidget {
  final AgentMessage message;
  const _ProgressBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(message.content,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline)),
      ),
    );
  }
}

class _TurnCompleteBubble extends StatelessWidget {
  final AgentMessage message;
  const _TurnCompleteBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cost = message.costUsd != null
        ? ' (\$${message.costUsd!.toStringAsFixed(4)})'
        : '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade400),
            const SizedBox(width: 4),
            Text('Done$cost',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final AgentMessage message;
  const _ErrorBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline,
                    size: 18, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(message.content,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer))),
              ],
            ),
            if (message.guidance != null &&
                message.guidance!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(message.guidance!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer
                            .withValues(alpha: 0.7),
                      )),
            ],
          ],
        ),
      ),
    );
  }
}
