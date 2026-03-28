import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task.dart';
import '../providers/server_provider.dart';
import '../services/api_client.dart';

class TaskNotifier extends StateNotifier<List<TaskInfo>> {
  final ApiClient? _api;
  Timer? _refreshTimer;

  TaskNotifier({ApiClient? api})
      : _api = api,
        super([]) {
    if (_api != null) _init();
  }

  void _init() {
    refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refresh(),
    );
  }

  Future<void> refresh() async {
    if (_api == null) return;
    try {
      final tasks = await _api!.getTasks();
      state = tasks;
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
    if (_api == null) return null;
    try {
      final resp = await _api!.createTask(
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
    if (_api == null) return;
    try {
      await _api!.cancelTask(id);
      await refresh();
    } catch (_) {}
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, List<TaskInfo>>((ref) {
  final server = ref.watch(serverProvider).server;
  if (server == null) return TaskNotifier();
  return TaskNotifier(
    api: ApiClient(baseUrl: server.url, token: server.token),
  );
});
