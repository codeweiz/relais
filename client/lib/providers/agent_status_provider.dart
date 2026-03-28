import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/agent_status.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

/// Manages aggregated status for all agents. Fetches initial snapshot via REST,
/// then relies entirely on /ws/status WebSocket for real-time activity updates.
class AgentStatusNotifier extends StateNotifier<Map<String, AgentStatusInfo>> {
  final ApiClient _api;
  final String _baseUrl;
  final String _token;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;

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
  }

  /// Fetches current agent status snapshot from the REST API.
  /// Call this for pull-to-refresh or after reconnection.
  Future<void> refresh() async {
    try {
      final statuses = await _api.getAgentStatuses();
      final map = <String, AgentStatusInfo>{};
      for (final s in statuses) {
        map[s.sessionId] = s;
      }
      if (!_disposed) state = map;
    } catch (_) {
      // Silently ignore refresh errors
    }
  }

  void _connectWebSocket() {
    if (_baseUrl.isEmpty || _disposed) return;
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
            final incomingActivity = json['activity'] as String? ?? '';
            debugPrint('[AgentStatus] $sessionId: status=${json['status']}, activity=${incomingActivity.length > 50 ? '${incomingActivity.substring(0, 50)}...' : incomingActivity}');
            final existing = state[sessionId];
            if (existing != null) {
              final updated = AgentStatusInfo(
                sessionId: sessionId,
                name: existing.name,
                provider: existing.provider,
                status: json['status'] as String? ?? existing.status,
                // Preserve last meaningful activity when incoming is empty
                // (mirrors server-side status_registry logic)
                activity: incomingActivity.isEmpty
                    ? existing.activity
                    : incomingActivity,
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
        if (_disposed) return;
        // Reconnect after a short delay and do a full REST refresh to catch
        // any updates that arrived while the connection was down.
        Future.delayed(const Duration(seconds: 3), () {
          if (!_disposed) {
            refresh();
            _connectWebSocket();
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
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
