import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/task.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

class TaskNotifier extends StateNotifier<List<TaskInfo>> {
  final ApiClient? _api;
  final String _baseUrl;
  final String _token;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _disposed = false;

  TaskNotifier({ApiClient? api, String baseUrl = '', String token = ''})
      : _api = api,
        _baseUrl = baseUrl,
        _token = token,
        super([]) {
    if (_api != null) _init();
  }

  void _init() {
    refresh();
    _connectWebSocket();
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
          // Refresh task list when tasks change
          if (type == 'task_completed' || type == 'session_created') {
            refresh();
          }
        }
      },
      onError: (_) {},
      onDone: () {
        if (_disposed) return;
        Future.delayed(const Duration(seconds: 3), () {
          if (!_disposed) {
            refresh();
            _connectWebSocket();
          }
        });
      },
    );
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
    try {
      final tasks = await api.getTasks();
      if (!_disposed) state = tasks;
    } catch (_) {}
  }

  Future<String?> createTask({
    required String title,
    String prompt = '',
    String priority = 'p1',
    String? targetAgent,
    String? sourceSessionId,
    String? cwd,
  }) async {
    final api = _api;
    if (api == null) return null;
    try {
      final resp = await api.createTask(
        title: title,
        prompt: prompt,
        priority: priority,
        targetAgent: targetAgent,
        sourceSessionId: sourceSessionId,
        cwd: cwd,
      );
      await refresh();
      return resp['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelTask(String id) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.cancelTask(id);
      await refresh();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, List<TaskInfo>>((ref) {
  final server = ref.watch(serverProvider).server;
  if (server == null) return TaskNotifier();
  return TaskNotifier(
    api: ApiClient(baseUrl: server.url, token: server.token),
    baseUrl: server.url,
    token: server.token,
  );
});
