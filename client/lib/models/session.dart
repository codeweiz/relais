enum SessionKind { terminal, agent }

enum SessionStatus {
  running, exited, ready, working, idle, crashed, initializing, waitingApproval, suspended;

  static SessionStatus fromString(String s) {
    return SessionStatus.values.firstWhere(
      (e) => e.name == s || e.name == s.replaceAll('_', ''),
      orElse: () => SessionStatus.running,
    );
  }
}

class Session {
  final String id;
  final String name;
  final SessionKind kind;
  final SessionStatus status;
  final String? parentId;
  final String createdAt;
  final String lastActive;
  final int? exitCode;
  final String? shell;
  final int cols;
  final int rows;

  const Session({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    this.parentId,
    required this.createdAt,
    required this.lastActive,
    this.exitCode,
    this.shell,
    this.cols = 80,
    this.rows = 24,
  });

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    id: json['id'] as String,
    name: json['name'] as String,
    kind: json['kind'] == 'agent' ? SessionKind.agent : SessionKind.terminal,
    status: SessionStatus.fromString(json['status'] as String? ?? 'running'),
    parentId: json['parent_id'] as String?,
    createdAt: json['created_at'] as String? ?? '',
    lastActive: json['last_active'] as String? ?? json['created_at'] as String? ?? '',
    exitCode: json['exit_code'] as int?,
    shell: json['shell'] as String?,
    cols: json['cols'] as int? ?? 80,
    rows: json['rows'] as int? ?? 24,
  );

  bool get isAgent => kind == SessionKind.agent;
  bool get isTerminal => kind == SessionKind.terminal;
}
