class AgentStatusInfo {
  final String sessionId;
  final String name;
  final String provider;
  final String status;
  final String activity;
  final double? costUsd;

  const AgentStatusInfo({
    required this.sessionId,
    required this.name,
    required this.provider,
    required this.status,
    required this.activity,
    this.costUsd,
  });

  factory AgentStatusInfo.fromJson(Map<String, dynamic> json) =>
      AgentStatusInfo(
        sessionId: json['session_id'] as String,
        name: json['name'] as String,
        provider: json['provider'] as String,
        status: json['status'] as String,
        activity: json['activity'] as String? ?? '',
        costUsd: (json['cost_usd'] as num?)?.toDouble(),
      );
}
