class TaskInfo {
  final String id;
  final String name;
  final String priority;
  final String status;
  final List<String> dependsOn;
  final String createdAt;
  final String? startedAt;
  final String? completedAt;
  final String? targetAgent;
  final String? sessionId;

  const TaskInfo({
    required this.id,
    required this.name,
    required this.priority,
    required this.status,
    this.dependsOn = const [],
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.targetAgent,
    this.sessionId,
  });

  factory TaskInfo.fromJson(Map<String, dynamic> json) => TaskInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        priority: json['priority'] as String? ?? 'P1',
        status: json['status'] as String,
        dependsOn: (json['depends_on'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: json['created_at'] as String,
        startedAt: json['started_at'] as String?,
        completedAt: json['completed_at'] as String?,
        targetAgent: json['target_agent'] as String?,
        sessionId: json['session_id'] as String?,
      );

  bool get isRunning => status == 'running';
  bool get isQueued => status == 'queued';
  bool get isUnassigned => targetAgent == null || targetAgent!.isEmpty;
}
