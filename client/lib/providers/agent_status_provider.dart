import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/agent_status.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

/// Manages aggregated status for all agents. Fetches initial snapshot via REST,
/// then subscribes to /ws/status for real-time activity updates.
class AgentStatusNotifier extends StateNotifier<Map<String, AgentStatusInfo>> {
  final ApiClient _api;
  final String _baseUrl;
  final String _token;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _refreshTimer;

  AgentStatusNotifier({
    required ApiClient api,
    required String baseUrl,
    required String token,
  })  : _api = api,
        _baseUrl = baseUrl,
        _token = token,
        super({}) {
    _init();
  }

  Future<void> _init() async {
    await refresh();
    _connectWebSocket();
    // Periodic refresh as fallback (every 5 seconds)
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    try {
      final statuses = await _api.getAgentStatuses();
      final map = <String, AgentStatusInfo>{};
      for (final s in statuses) {
        map[s.sessionId] = s;
      }
      state = map;
    } catch (_) {
      // Silently ignore refresh errors
    }
  }

  void _connectWebSocket() {
    if (_baseUrl.isEmpty) return;
    final wsUrl = _baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse('$wsUrl/ws/status?token=$_token');
    _channel = WebSocketChannel.connect(uri);

    _sub = _channel!.stream.listen(
      (data) {
        if (data is String) {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'agent_activity') {
            final sessionId = json['session_id'] as String;
            final existing = state[sessionId];
            if (existing != null) {
              final updated = AgentStatusInfo(
                sessionId: sessionId,
                name: existing.name,
                provider: existing.provider,
                status: json['status'] as String? ?? existing.status,
                activity: json['activity'] as String? ?? '',
                costUsd: existing.costUsd,
              );
              state = {...state, sessionId: updated};
            }
          } else if (type == 'session_deleted') {
            final sessionId = json['session_id'] as String;
            state = Map.from(state)..remove(sessionId);
          } else if (type == 'session_created') {
            // New session — refresh to get full info
            refresh();
          }
        }
      },
      onError: (_) {},
      onDone: () {
        // Reconnect after a short delay
        Future.delayed(const Duration(seconds: 3), _connectWebSocket);
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

/// Provider for agent status. Requires server connection to be active.
final agentStatusProvider =
    StateNotifierProvider<AgentStatusNotifier, Map<String, AgentStatusInfo>>(
        (ref) {
  final server = ref.watch(serverProvider).server;
  if (server == null) {
    return AgentStatusNotifier(
      api: ApiClient(baseUrl: '', token: ''),
      baseUrl: '',
      token: '',
    );
  }
  return AgentStatusNotifier(
    api: ApiClient(baseUrl: server.url, token: server.token),
    baseUrl: server.url,
    token: server.token,
  );
});
