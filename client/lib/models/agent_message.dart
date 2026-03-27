enum AgentMessageType {
  user, text, thinking, toolUse, toolResult, progress, turnComplete, error
}

class AgentMessage {
  final String id;
  final AgentMessageType type;
  final String content;
  final DateTime timestamp;
  final int? seq;
  final bool streaming;
  final String? toolName;
  final String? toolId;
  final String? toolInput;
  final String? toolOutput;
  final bool? isError;
  final String? severity;
  final String? guidance;
  final String? source;
  final double? costUsd;

  const AgentMessage({
    required this.id,
    required this.type,
    required this.content,
    required this.timestamp,
    this.seq,
    this.streaming = false,
    this.toolName,
    this.toolId,
    this.toolInput,
    this.toolOutput,
    this.isError,
    this.severity,
    this.guidance,
    this.source,
    this.costUsd,
  });

  factory AgentMessage.fromServerEvent(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final seq = json['seq'] as int?;
    final now = DateTime.now();

    switch (type) {
      case 'user_message':
        return AgentMessage(
          id: 'user-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.user,
          content: json['text'] as String? ?? '',
          timestamp: now,
          seq: seq,
          source: json['source'] as String?,
        );
      case 'text':
        return AgentMessage(
          id: 'text-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.text,
          content: json['content'] as String? ?? '',
          timestamp: now,
          seq: seq,
          streaming: json['streaming'] as bool? ?? false,
        );
      case 'thinking':
        return AgentMessage(
          id: 'thinking-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.thinking,
          content: json['content'] as String? ?? '',
          timestamp: now,
          seq: seq,
        );
      case 'tool_use':
        return AgentMessage(
          id: 'tool_use-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.toolUse,
          content: 'Using ${json['name']}',
          timestamp: now,
          seq: seq,
          toolName: json['name'] as String?,
          toolId: json['id'] as String?,
          toolInput: json['input']?.toString(),
        );
      case 'tool_result':
        return AgentMessage(
          id: 'tool_result-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.toolResult,
          content: json['output'] as String? ?? '',
          timestamp: now,
          seq: seq,
          toolId: json['id'] as String?,
          toolOutput: json['output'] as String?,
          isError: json['is_error'] as bool?,
        );
      case 'progress':
        return AgentMessage(
          id: 'progress-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.progress,
          content: json['message'] as String? ?? '',
          timestamp: now,
          seq: seq,
        );
      case 'turn_complete':
        return AgentMessage(
          id: 'turn-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.turnComplete,
          content: 'Turn complete',
          timestamp: now,
          seq: seq,
          costUsd: (json['cost_usd'] as num?)?.toDouble(),
        );
      case 'error':
        return AgentMessage(
          id: 'error-${seq ?? now.millisecondsSinceEpoch}',
          type: AgentMessageType.error,
          content: json['message'] as String? ?? 'Unknown error',
          timestamp: now,
          seq: seq,
          severity: json['severity'] as String?,
          guidance: json['guidance'] as String?,
        );
      default:
        return AgentMessage(
          id: 'unknown-${now.millisecondsSinceEpoch}',
          type: AgentMessageType.text,
          content: '[Unknown: $type]',
          timestamp: now,
        );
    }
  }
}
